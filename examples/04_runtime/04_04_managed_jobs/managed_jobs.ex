defmodule Jido.Examples.ManagedJobs.Submit do
  @moduledoc "Portable job intent. The work adapter remains in caller context."
  @schema Zoi.struct(__MODULE__, %{job_id: Zoi.string(), value: Zoi.integer()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.ManagedJobs.CancelJob do
  @moduledoc false
  @schema Zoi.struct(__MODULE__, %{job_id: Zoi.string()})
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.Examples.ManagedJobs.Jobs do
  @moduledoc "A Plugin runtime owns linked job tasks and returns terminal Signals."
  use Jido.Plugin
  alias Jido.Examples.ManagedJobs.{Submit, CancelJob, Runtime}
  def directives(_), do: [Submit, CancelJob]

  def validate_directive(%{__struct__: module} = directive, _),
    do: Zoi.parse(module.schema(), directive)

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  def await_ready(runtime, _), do: GenServer.call(runtime, :ready)

  def dispatch(runtime, directive, context, _),
    do: GenServer.call(runtime, {:dispatch, directive, context.turn_context})
end

defmodule Jido.Examples.ManagedJobs.Runtime do
  @moduledoc false
  use GenServer
  alias Jido.Examples.ManagedJobs.{Submit, CancelJob}
  def start_link(init), do: GenServer.start_link(__MODULE__, init)
  def jobs(runtime), do: GenServer.call(runtime, :jobs)
  @impl true
  def init(init) do
    Process.flag(:trap_exit, true)
    {:ok, %{server: init.agent_server, jobs: %{}}}
  end

  @impl true
  def handle_call(:ready, _, state), do: {:reply, :ok, state}
  def handle_call(:jobs, _, state), do: {:reply, Map.keys(state.jobs), state}

  def handle_call({:dispatch, %Submit{} = job, context}, _, state) do
    work = Map.get(context, :work, fn value -> {:ok, Integer.to_string(value * 2)} end)
    task = Task.async(fn -> work.(job.value) end)
    {:reply, :ok, %{state | jobs: Map.put(state.jobs, job.job_id, task)}}
  end

  def handle_call({:dispatch, %CancelJob{job_id: id}, _}, _, state) do
    {task, jobs} = Map.pop(state.jobs, id)
    if task, do: Task.shutdown(task, :brutal_kill)
    {:reply, :ok, %{state | jobs: jobs}}
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    finish(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _, reason}, state),
    do: finish(ref, {:error, reason}, state)

  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  defp finish(ref, result, state) do
    case Enum.find(state.jobs, fn {_, task} -> task.ref == ref end) do
      nil ->
        {:noreply, state}

      {id, _} ->
        data =
          case result do
            {:ok, value} when is_binary(value) -> %{job_id: id, status: :completed, result: value}
            other -> %{job_id: id, status: :failed, result: inspect(other)}
          end

        signal = Jido.Examples.ManagedJobs.settle_signal!(input: data)
        :ok = Jido.AgentServer.cast(state.server, signal)
        {:noreply, %{state | jobs: Map.delete(state.jobs, id)}}
    end
  end

  @impl true
  def terminate(_, state) do
    Enum.each(state.jobs, fn {_, task} -> Task.shutdown(task, :brutal_kill) end)
    :ok
  end
end

defmodule Jido.Examples.ManagedJobs.Start do
  @moduledoc false
  use Jido.Action,
    name: "example_managed_job_start",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), value: Zoi.integer()})

  def run(input, %{agent_state: state} = context) do
    cond do
      state.status == :running or input.job_id in state.seen ->
        {:error, Jido.Action.Error.validation_error("job is active or already used")}

      Map.has_key?(context, :work) and not is_function(context.work, 1) ->
        {:error, Jido.Action.Error.validation_error("work must be a function with one argument")}

      true ->
        {:ok,
         %{
           state
           | job_id: input.job_id,
             seen: state.seen ++ [input.job_id],
             status: :running,
             result: ""
         }, [struct!(Jido.Examples.ManagedJobs.Submit, input)]}
    end
  end
end

defmodule Jido.Examples.ManagedJobs.Settle do
  @moduledoc false
  use Jido.Action,
    name: "example_managed_job_settle",
    schema:
      Zoi.object(%{
        job_id: Zoi.string(),
        status: Zoi.enum([:completed, :failed]),
        result: Zoi.string()
      })

  def run(%{job_id: id} = input, %{agent_state: %{job_id: id, status: :running} = state}),
    do: {:ok, %{state | status: input.status, result: input.result}}

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("job result is stale")}
end

defmodule Jido.Examples.ManagedJobs.Cancel do
  @moduledoc false
  use Jido.Action,
    name: "example_managed_job_cancel",
    schema: Zoi.object(%{job_id: Zoi.string()})

  def run(%{job_id: id}, %{agent_state: %{job_id: id, status: :running} = state}),
    do:
      {:ok, %{state | status: :cancelled},
       [struct!(Jido.Examples.ManagedJobs.CancelJob, job_id: id)]}

  def run(_, _), do: {:error, Jido.Action.Error.validation_error("job is not running")}
end

defmodule Jido.Examples.ManagedJobs do
  @moduledoc """
  Commits a job request before a Plugin starts its task. A later Signal commits
  the result. Cancellation stops the task. Agent shutdown stops the capability.
  A capability crash loses active work: cancel the pending request and submit a
  new ID. Automatic replay needs an application recovery and idempotency policy.
  """
  use Jido.Agent, name: "example_managed_jobs"

  agent do
    schema Zoi.object(%{
             job_id: Zoi.string() |> Zoi.default(""),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             status:
               Zoi.enum([:idle, :running, :completed, :failed, :cancelled]) |> Zoi.default(:idle),
             result: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.ManagedJobs.Jobs
  end

  routes do
    signal_source "/examples/jobs"

    route "examples.jobs.start", Jido.Examples.ManagedJobs.Start do
      define :start_job, args: [:job_id, :value]
    end

    route "examples.jobs.cancel", Jido.Examples.ManagedJobs.Cancel do
      define :cancel_job, args: [:job_id]
    end

    route "examples.jobs.settle", Jido.Examples.ManagedJobs.Settle do
      define :settle
    end
  end
end
