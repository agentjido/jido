defmodule Jido.Examples.Factory.Orchestrator.Command do
  @moduledoc false
  use Jido.Action,
    name: "factory_orchestrator_command",
    schema: Jido.Examples.Factory.Protocol.command_schema()

  alias Jido.Examples.Factory.{Async, Orchestrator, Plan, Protocol}

  def run(%{operation: :status}, %{agent_state: state}), do: {:ok, state}

  def run(%{operation: :submit} = input, %{agent_state: state} = context) do
    case state.jobs[input.request_id] do
      %{goal: goal} when goal == input.goal -> {:ok, state}
      nil -> submit(input, state, context.agent_id)
      _ -> Protocol.invalid("Request ID belongs to a different goal")
    end
  end

  def run(input, %{agent_state: state} = context) do
    case state.jobs[input.job_id] do
      nil -> Protocol.invalid("Job was not found")
      job -> control(input.operation, job, state, context.agent_id)
    end
  end

  defp submit(input, state, agent_id) do
    cond do
      not state.ready ->
        Protocol.invalid("Departments are not started")

      Enum.any?(state.jobs, fn {_, job} -> job.status in [:running, :paused] end) ->
        Protocol.invalid("This example accepts one active goal at a time")

      String.trim(input.goal) == "" or map_size(state.jobs) >= 20 ->
        Protocol.invalid("Supply a goal; this example holds at most 20 jobs")

      true ->
        job = %{
          id: input.request_id,
          goal: input.goal,
          status: :running,
          stages: Plan.stages(),
          error: ""
        }

        state = %{state | jobs: Map.put(state.jobs, job.id, job)}

        {state, event} =
          Protocol.event(state, job, "Plan accepted: research + design, then build, then quality")

        {state, work} = Orchestrator.launch(state, job.id, agent_id)
        {:ok, state, [event | work]}
    end
  end

  defp control(:pause, %{status: :running} = job, state, _) do
    job = %{job | status: :paused}
    state = %{state | jobs: Map.put(state.jobs, job.id, job)}
    {state, event} = Protocol.event(state, job, "Paused; active department calls can finish")
    {:ok, state, [event]}
  end

  defp control(:resume, %{status: :paused} = job, state, agent_id) do
    job = %{job | status: :running}
    state = %{state | jobs: Map.put(state.jobs, job.id, job)}
    {state, event} = Protocol.event(state, job, "Resumed")
    {state, work} = Orchestrator.launch(state, job.id, agent_id)
    {:ok, state, [event | work]}
  end

  defp control(:cancel, %{status: status} = job, state, _) when status in [:running, :paused] do
    job = %{job | status: :cancelled}
    directives = Enum.map(state.active, fn {id, _} -> %Async.Cancel{request_id: id} end)
    state = %{state | active: %{}, jobs: Map.put(state.jobs, job.id, job)}
    {state, event} = Protocol.event(state, job, "Cancelled; late results will be rejected")
    {:ok, state, directives ++ [event, %Async.Forget{context_key: job.id}]}
  end

  defp control(_, _, _, _),
    do: Protocol.invalid("Operation is not valid for the current job state")
end

defmodule Jido.Examples.Factory.Orchestrator.Settle do
  @moduledoc false
  use Jido.Action,
    name: "factory_orchestrator_settle",
    schema: Jido.Examples.Factory.Async.result_schema()

  alias Jido.Examples.Factory.{Async, Orchestrator, Protocol}

  def run(input, %{agent_state: state, agent_id: agent_id}) do
    case state.active[input.request_id] do
      nil -> Protocol.invalid("Department result is stale")
      active -> settle(input, active, state, agent_id)
    end
  end

  defp settle(%{status: :failed} = input, active, state, _) do
    job = %{state.jobs[active.job_id] | status: :failed, error: input.error}

    directives =
      for {id, _} <- state.active, id != input.request_id, do: %Async.Cancel{request_id: id}

    state = %{state | jobs: Map.put(state.jobs, job.id, job), active: %{}}

    {state, event} =
      Protocol.event(state, job, "Department #{active.stage} failed: #{input.error}")

    {:ok, state, directives ++ [event, %Async.Forget{context_key: job.id}]}
  end

  defp settle(input, active, state, agent_id) do
    result = input.result

    if result[:attempt_id] == input.request_id and result[:job_id] == active.job_id and
         result[:department] == active.stage and is_binary(result[:text]) do
      job = state.jobs[active.job_id]
      stage = %{job.stages[active.stage] | status: :completed, text: result.text}
      job = %{job | stages: Map.put(job.stages, active.stage, stage)}
      done? = Enum.all?(job.stages, fn {_, item} -> item.status == :completed end)
      job = if done?, do: %{job | status: :completed}, else: job

      state = %{
        state
        | jobs: Map.put(state.jobs, job.id, job),
          active: Map.delete(state.active, input.request_id)
      }

      {state, event} = Protocol.event(state, job, "#{active.stage} artifact received")
      {state, work} = Orchestrator.launch(state, job.id, agent_id)
      cleanup = if done?, do: [%Async.Forget{context_key: job.id}], else: []
      {:ok, state, [event | work ++ cleanup]}
    else
      Protocol.invalid("Department result does not match its active attempt")
    end
  end
end

defmodule Jido.Examples.Factory.Orchestrator do
  @moduledoc "Runs an explicit dependency plan through four department Agents, with at most two active steps."
  use Jido.Agent, name: "factory_orchestrator"
  alias Jido.Agent.Directive
  alias Jido.Examples.Factory.{Async, Department, Plan}

  agent do
    schema Zoi.object(%{
             ready: Zoi.boolean() |> Zoi.default(false),
             jobs: Zoi.map() |> Zoi.default(%{}),
             events: Zoi.list(Zoi.map()) |> Zoi.default([]),
             active: Zoi.map() |> Zoi.default(%{}),
             sequence: Zoi.integer() |> Zoi.default(0)
           })

    plugin Async
  end

  routes do
    signal_source "/examples/factory/orchestrator"

    route "factory.departments.boot" do
      action _input, name: "factory_departments_boot", context: context do
        Jido.Examples.Factory.Orchestrator.start_departments(context.agent_state)
      end

      define :boot
    end

    route "factory.command", __MODULE__.Command
    route "factory.inspect", Jido.Examples.Factory.Inspection
    route "factory.async.result", __MODULE__.Settle
    route "jido.agent.child.*", Jido.Examples.KeepState
  end

  @doc false
  def start_departments(%{ready: true}),
    do: Jido.Examples.Factory.Protocol.invalid("Departments are already started")

  def start_departments(state) do
    directives =
      Enum.map(Plan.steps(), fn step ->
        Directive.spawn_agent(Department, step.id,
          opts: %{initial_state: %{department: step.id}, exec_opts: [timeout: 50_000]}
        )
      end)

    {:ok, %{state | ready: true}, directives}
  end

  @doc false
  def launch(state, job_id, agent_id) do
    job = state.jobs[job_id]

    ready =
      if job.status == :running do
        Plan.steps()
        |> Enum.filter(fn step ->
          job.stages[step.id].status == :pending and
            Enum.all?(step.depends_on, &(job.stages[&1].status == :completed))
        end)
        |> Enum.take(max(0, 2 - map_size(state.active)))
      else
        []
      end

    Enum.reduce(ready, {state, []}, fn step, {state, directives} ->
      job = state.jobs[job_id]
      attempt_id = "#{job.id}/#{step.id}/1"
      inputs = Map.new(step.depends_on, &{&1, job.stages[&1].text})

      request = %Async.Request{
        request_id: attempt_id,
        context_key: job.id,
        kind: :department,
        input: %{
          agent_id: "#{agent_id}/#{step.id}",
          work: %{
            job_id: job.id,
            attempt_id: attempt_id,
            goal: job.goal,
            brief: step.brief,
            inputs: inputs
          }
        }
      }

      job = put_in(job.stages[step.id].status, :running)
      active = Map.put(state.active, attempt_id, %{job_id: job.id, stage: step.id})
      {%{state | jobs: Map.put(state.jobs, job.id, job), active: active}, directives ++ [request]}
    end)
  end
end
