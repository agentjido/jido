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
end

defmodule Jido.Examples.Factory.FlowFactory.Cancel do
  @moduledoc "Stops the runtime-owned Flow execution."
  @schema Zoi.struct(__MODULE__, %{})
  defstruct []
  def schema, do: @schema
end

defmodule Jido.Examples.Factory.FlowFactory.Runner do
  @moduledoc "A Plugin owns the asynchronous Exec handle outside portable Agent state."
  use Jido.Plugin
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Run}

  def directives(_), do: [Run, Cancel]
  def validate_directive(%{__struct__: module} = value, _), do: Zoi.parse(module.schema(), value)
  def child_spec(init), do: Supervisor.child_spec({__MODULE__.Runtime, init}, id: __MODULE__)
  def await_ready(pid, _), do: GenServer.call(pid, :ready)

  def dispatch(pid, directive, context, _),
    do: GenServer.call(pid, {directive, context.turn_context})
end

defmodule Jido.Examples.Factory.FlowFactory.Runner.Runtime do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.FlowFactory.{Cancel, Pipeline, Run}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def init(init), do: {:ok, %{init: init, handle: nil, mission_id: nil}}
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

    handle =
      Jido.Exec.run_async(Pipeline, Map.from_struct(intent), context,
        jido: state.init.jido,
        max_concurrency: 3,
        timeout: timeout
      )

    {:reply, :ok, %{state | handle: handle, mission_id: intent.mission_id}}
  end

  def handle_call({%Run{}, _}, _, state), do: {:reply, {:error, :already_running}, state}

  def handle_call({:progress, signal}, _, state) do
    # One sender preserves progress-before-finish order without holding an Agent turn open.
    Server.cast(state.init.agent_server, signal)
    {:reply, :ok, state}
  end

  def handle_call({%Cancel{}, _}, _, state) do
    if state.handle, do: Jido.Exec.cancel(state.handle)
    {:reply, :ok, %{state | handle: nil}}
  end

  def handle_info(_, %{handle: nil} = state), do: {:noreply, state}

  def handle_info(message, state) do
    case Jido.Exec.handle_message(state.handle, message) do
      {:done, result} ->
        data =
          case result do
            {:ok, output} ->
              %{status: :completed, output: output, error: ""}

            {:error, error} ->
              %{status: :failed, output: %{}, error: Jido.Examples.Factory.Error.message(error)}
          end

        signal =
          Jido.Signal.new!("factory.flow.finished", Map.put(data, :mission_id, state.mission_id),
            source: "/factory/flow"
          )

        Server.cast(state.init.agent_server, signal)
        {:noreply, %{state | handle: nil}}

      :ignore ->
        {:noreply, state}
    end
  end

  def terminate(_, state) do
    if state.handle, do: Jido.Exec.cancel(state.handle)
    :ok
  end
end
