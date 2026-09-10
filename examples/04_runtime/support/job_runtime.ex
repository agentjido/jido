defmodule Jido.Examples.Runtime.JobRunner do
  @moduledoc "A runtime port for managed job work."

  alias Jido.Action.Error
  alias Jido.Examples.Runtime.DoubleJobRunner

  @callback run(client :: term(), value :: integer()) :: {:ok, String.t()} | {:error, term()}

  @doc "Returns the configured runner, or the deterministic local runner."
  @spec fetch(map()) :: {:ok, {module(), term()}} | {:error, Exception.t()}
  def fetch(context) when is_map(context) do
    case Map.get(context, :job_runner, {DoubleJobRunner, nil}) do
      {module, client} when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
          {:ok, {module, client}}
        else
          {:error, Error.validation_error("job runner must implement run/2")}
        end

      _other ->
        {:error, Error.validation_error("job runner must be a {module, client} pair")}
    end
  end
end

defmodule Jido.Examples.Runtime.DoubleJobRunner do
  @moduledoc "A deterministic local runner used by the default example path."

  @behaviour Jido.Examples.Runtime.JobRunner

  @impl true
  def run(_client, value), do: {:ok, Integer.to_string(value * 2)}
end

defmodule Jido.Examples.Runtime.JobRuntime.Submit do
  @moduledoc "Portable intent to start one managed job."

  @schema Zoi.struct(__MODULE__, %{job_id: Zoi.string(), value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.Runtime.JobRuntime.Cancel do
  @moduledoc "Portable intent to cancel one managed job."

  @schema Zoi.struct(__MODULE__, %{job_id: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema
end

defmodule Jido.Examples.Runtime.JobRuntime do
  @moduledoc "A Plugin that owns linked job tasks and returns terminal Signals."

  use Jido.Plugin

  alias Jido.Examples.Runtime.JobRuntime.{Cancel, Server, Submit}

  @impl true
  def directives(_opts), do: [Submit, Cancel]

  @impl true
  def validate_directive(%{__struct__: module} = directive, _opts),
    do: Zoi.parse(module.schema(), directive)

  def child_spec(init), do: Supervisor.child_spec({Server, init}, id: __MODULE__)

  @impl true
  def await_ready(runtime, _opts), do: GenServer.call(runtime, :ready)

  @impl true
  def dispatch(runtime, directive, context, _opts),
    do: GenServer.call(runtime, {:dispatch, directive, context.turn_context})

  @doc "Builds the terminal Signal sent by the managed runtime."
  def settle_signal!(data) do
    Jido.Signal.new!("examples.runtime.jobs.settle", data,
      source: "/examples/runtime/job_runtime"
    )
  end
end

defmodule Jido.Examples.Runtime.JobRuntime.Server do
  @moduledoc false

  use GenServer

  alias Jido.Examples.Runtime.{JobRunner, JobRuntime}
  alias Jido.Examples.Runtime.JobRuntime.{Cancel, Submit}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def jobs(runtime), do: GenServer.call(runtime, :jobs)

  @impl true
  def init(init) do
    Process.flag(:trap_exit, true)
    {:ok, %{agent_server: init.agent_server, jobs: %{}}}
  end

  @impl true
  def handle_call(:ready, _from, state), do: {:reply, :ok, state}
  def handle_call(:jobs, _from, state), do: {:reply, Map.keys(state.jobs), state}

  def handle_call({:dispatch, %Submit{} = job, context}, _from, state) do
    with {:ok, {module, client}} <- JobRunner.fetch(context) do
      task = Task.async(fn -> module.run(client, job.value) end)
      {:reply, :ok, %{state | jobs: Map.put(state.jobs, job.job_id, task)}}
    end
  end

  def handle_call({:dispatch, %Cancel{job_id: job_id}, _context}, _from, state) do
    {task, jobs} = Map.pop(state.jobs, job_id)
    if task, do: Task.shutdown(task, :brutal_kill)
    {:reply, :ok, %{state | jobs: jobs}}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state),
    do: finish(ref, {:error, reason}, state)

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Enum.each(state.jobs, fn {_id, task} -> Task.shutdown(task, :brutal_kill) end)
    :ok
  end

  defp finish(ref, result, state) do
    case Enum.find(state.jobs, fn {_id, task} -> task.ref == ref end) do
      nil ->
        {:noreply, state}

      {job_id, _task} ->
        data =
          case result do
            {:ok, value} when is_binary(value) ->
              %{job_id: job_id, status: :completed, result: value}

            other ->
              %{job_id: job_id, status: :failed, result: inspect(other)}
          end

        :ok = Jido.AgentServer.cast(state.agent_server, JobRuntime.settle_signal!(data))
        {:noreply, %{state | jobs: Map.delete(state.jobs, job_id)}}
    end
  end
end
