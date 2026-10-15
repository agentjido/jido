defmodule Jido.Examples.Factory.FlowFactory.Run do
  @moduledoc "Portable intent to start the factory Flow after the mission commit."
  @schema Zoi.struct(__MODULE__, %{
            mission_id: Zoi.string(),
            goal: Zoi.string(),
            security: Zoi.boolean()
          })
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
  def validate(%__MODULE__{} = value), do: Zoi.parse(@schema, value)
end

defmodule Jido.Examples.Factory.FlowFactory.Cancel do
  @moduledoc "Stops the runtime-owned Flow execution."
  @schema Zoi.struct(__MODULE__, %{})
  defstruct []
  def schema, do: @schema
  def validate(%__MODULE__{} = value), do: Zoi.parse(@schema, value)
end

defmodule Jido.Examples.Factory.FlowFactory.Runner do
  @moduledoc "A Plugin owns a started execution outside portable Agent state."
  use Jido.Plugin

  @impl true
  defdelegate directives(opts), to: Jido.Examples.Factory.FlowFactory.Runner.Agent

  @impl true
  defdelegate child_spec(init), to: Jido.Examples.Factory.FlowFactory.Runner.Server

  @impl true
  defdelegate await_ready(runtime, opts), to: Jido.Examples.Factory.FlowFactory.Runner.Server

  @impl true
  defdelegate dispatch(runtime, directive, context, opts),
    to: Jido.Examples.Factory.FlowFactory.Runner.Server
end

defmodule Jido.Examples.Factory.FlowFactory.Runner.Agent do
  @behaviour Jido.Plugin
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Run}

  @impl true
  def directives(_), do: [Run, Cancel]
end

defmodule Jido.Examples.Factory.FlowFactory.Runner.Server do
  @behaviour Jido.Plugin

  @impl true
  def child_spec(init),
    do:
      Supervisor.child_spec({Jido.Examples.Factory.FlowFactory.Runner.Runtime, init},
        id: Jido.Examples.Factory.FlowFactory.Runner
      )

  @impl true
  def await_ready(pid, _), do: GenServer.call(pid, :ready)

  @impl true
  def dispatch(pid, directive, context, _),
    do: GenServer.call(pid, {directive, context.turn_context})
end

defmodule Jido.Examples.Factory.FlowFactory.Runner.Runtime do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Pipeline, Run}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  def init(init) do
    Process.flag(:trap_exit, true)
    {:ok, %{init: init, handle: nil, mission_id: nil}}
  end

  def handle_call(:ready, _, state), do: {:reply, :ok, state}

  def handle_call({%Run{} = intent, context}, _, %{handle: nil} = state) do
    timeout = Map.get(context, :flow_timeout, 600_000)

    context =
      Map.merge(context, %{
        factory_jido: state.init.jido,
        mission_id: intent.mission_id,
        progress_sink: self(),
        flow_deadline: System.monotonic_time(:millisecond) + timeout
      })

    runner = Jido.exec_runner_name(state.init.jido)
    id = Jido.Signal.ID.generate!()
    owner = self()

    case Jido.Exec.start(runner, id, Pipeline, Map.from_struct(intent), context,
           mode: :local,
           owner: owner,
           max_concurrency: 3,
           timeout: timeout,
           on_complete: fn id, _ -> send(owner, {:flow_complete, id}) end
         ) do
      {:ok, pid} ->
        handle = %{runner: runner, id: id, pid: pid, ref: Process.monitor(pid)}
        {:reply, :ok, %{state | handle: handle, mission_id: intent.mission_id}}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({%Run{}, _}, _, state), do: {:reply, {:error, :already_running}, state}

  def handle_call({:progress, signal}, _, state) do
    # One sender preserves progress-before-finish order without holding an Agent turn open.
    Server.cast(state.init.agent_server, signal)
    {:reply, :ok, state}
  end

  def handle_call({%Cancel{}, _}, _, state) do
    release(state.handle)
    {:reply, :ok, %{state | handle: nil}}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}
  def handle_info(_, %{handle: nil} = state), do: {:noreply, state}

  def handle_info({:flow_complete, id}, %{handle: %{id: id} = handle} = state) do
    result = Jido.Exec.result(handle.runner, id)
    :ok = release(handle)

    data =
      case result do
        {:ok, output} ->
          %{status: :completed, output: output, error: ""}

        {:ok, output, _effects} ->
          %{status: :completed, output: output, error: ""}

        {:error, error} ->
          %{status: :failed, output: %{}, error: Jido.Examples.Factory.Error.message(error)}
      end

    signal =
      Jido.Signal.new!(
        "examples.factory.flow.finished",
        Map.put(data, :mission_id, state.mission_id),
        source: "/examples/factory/flow"
      )

    Server.cast(state.init.agent_server, signal)
    {:noreply, %{state | handle: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{handle: %{ref: ref}} = state),
    do: {:stop, {:execution_worker_exited, reason}, state}

  def handle_info(_message, state), do: {:noreply, state}

  defp release(nil), do: :ok

  defp release(handle) do
    Process.demonitor(handle.ref, [:flush])
    Runic.Runner.cancel(handle.runner, handle.id)
  end

  def terminate(_, state) do
    release(state.handle)
    :ok
  end
end
