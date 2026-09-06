defmodule Jido.Examples.Applications.FixedGroup.Signals do
  alias Jido.Signal

  def work_requested(group_id, generation, target_id, task) do
    Signal.new!(
      "fixed.work.requested",
      %{
        group_id: group_id,
        generation: generation,
        target_id: target_id,
        task_id: task.id,
        value: task.value
      },
      source: "/fixed/controller"
    )
  end

  def environment_apply(group_id, generation, worker_id, task_id, result) do
    Signal.new!(
      "fixed.environment.apply",
      %{
        group_id: group_id,
        generation: generation,
        worker_id: worker_id,
        task_id: task_id,
        result: result
      },
      source: "/fixed/worker/#{worker_id}"
    )
  end

  def work_applied(data) do
    Signal.new!("fixed.work.applied", data, source: "/fixed/environment")
  end

  def member_ready(group_id, generation, member_id, role, restarted?) do
    Signal.new!(
      "fixed.control.member.ready",
      %{
        group_id: group_id,
        generation: generation,
        member_id: member_id,
        role: role,
        restarted: restarted?
      },
      source: "/fixed/controller"
    )
  end
end

defmodule Jido.Examples.Applications.FixedGroup.Work do
  use Jido.Action, name: "fixed_group_work"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    if input.group_id == state.group_id and input.generation == state.generation and
         input.target_id == state.member_id do
      result = input.value * 2

      signal =
        Signals.environment_apply(
          state.group_id,
          state.generation,
          state.member_id,
          input.task_id,
          result
        )

      next_state = %{state | handled: state.handled ++ [input.task_id]}
      {:ok, next_state, [Directive.emit(signal, @dispatch)]}
    else
      {:ok, %{state | ignored: state.ignored + 1}}
    end
  end
end

defmodule Jido.Examples.Applications.FixedGroup.WorkerAgent do
  use Jido.Agent, name: "fixed_group_worker"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             member_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             handled: Zoi.list(Zoi.string()) |> Zoi.default([]),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :fixed_group_bus, paths: ["fixed.work.requested"]]
  end

  routes do
    route "fixed.work.requested", Jido.Examples.Applications.FixedGroup.Work
  end
end

defmodule Jido.Examples.Applications.FixedGroup.ApplyResult do
  use Jido.Action, name: "fixed_group_apply_result"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    cond do
      input.group_id != state.group_id or input.generation != state.generation ->
        {:ok, %{state | ignored: state.ignored + 1}}

      Map.has_key?(state.results, input.task_id) ->
        {:ok, %{state | duplicates: state.duplicates + 1}}

      true ->
        result = %{
          task_id: input.task_id,
          worker_id: input.worker_id,
          result: input.result
        }

        next_state = %{state | results: Map.put(state.results, input.task_id, result)}

        applied =
          Signals.work_applied(%{
            group_id: state.group_id,
            generation: state.generation,
            task_id: input.task_id,
            worker_id: input.worker_id,
            result: input.result
          })

        {:ok, next_state, [Directive.emit(applied, @dispatch)]}
    end
  end
end

defmodule Jido.Examples.Applications.FixedGroup.EnvironmentAgent do
  use Jido.Agent, name: "fixed_group_environment"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             results: Zoi.map() |> Zoi.default(%{}),
             duplicates: Zoi.integer() |> Zoi.default(0),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :fixed_group_bus, paths: ["fixed.environment.apply"]]
  end

  routes do
    route "fixed.environment.apply", Jido.Examples.Applications.FixedGroup.ApplyResult
  end
end

defmodule Jido.Examples.Applications.FixedGroup.Start do
  use Jido.Action, name: "fixed_group_start"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.{EnvironmentAgent, WorkerAgent}

  @impl Jido.Action
  def run(%{group_id: group_id, worker_count: worker_count}, context) do
    state = context.agent_state
    generation = state.generation + 1
    environment_id = "#{group_id}/environment"
    worker_ids = Enum.map(1..worker_count, &"#{group_id}/worker-#{&1}")

    desired =
      Enum.reduce(worker_ids, %{environment_id => "environment"}, fn worker_id, desired ->
        Map.put(desired, worker_id, "worker")
      end)

    environment =
      Directive.spawn_agent(EnvironmentAgent, :environment,
        opts: %{
          id: environment_id,
          initial_state: %{group_id: group_id, generation: generation}
        },
        meta: %{role: "environment"},
        restart: :transient
      )

    workers =
      worker_ids
      |> Enum.with_index(1)
      |> Enum.map(fn {worker_id, index} ->
        Directive.spawn_agent(WorkerAgent, "worker-#{index}",
          opts: %{
            id: worker_id,
            initial_state: %{
              group_id: group_id,
              member_id: worker_id,
              generation: generation
            }
          },
          meta: %{role: "worker", index: index},
          restart: :transient
        )
      end)

    next_state = %{
      state
      | group_id: group_id,
        generation: generation,
        desired: desired,
        worker_ids: worker_ids,
        environment_id: environment_id,
        ready_members: [],
        member_starts: %{},
        next_worker: 0,
        submitted: %{},
        results: %{}
    }

    {:ok, next_state, [environment | workers]}
  end
end

defmodule Jido.Examples.Applications.FixedGroup.RecordMemberReady do
  use Jido.Action, name: "fixed_group_record_member_ready"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  @impl Jido.Action
  def run(%{child_id: child_id, meta: meta}, context) do
    state = context.agent_state
    role = Map.fetch!(state.desired, child_id)
    starts = Map.update(state.member_starts, child_id, 1, &(&1 + 1))

    ready =
      state.ready_members
      |> List.insert_at(-1, child_id)
      |> Enum.uniq()
      |> Enum.sort()

    next_state = %{state | ready_members: ready, member_starts: starts}

    signal =
      Signals.member_ready(
        state.group_id,
        state.generation,
        child_id,
        role,
        Map.get(meta, :restarted, false)
      )

    {:ok, next_state, [Directive.emit(signal, @dispatch)]}
  end
end

defmodule Jido.Examples.Applications.FixedGroup.Submit do
  use Jido.Action, name: "fixed_group_submit"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.Signals

  @dispatch {:bus, [target: :fixed_group_bus]}

  @impl Jido.Action
  def run(%{tasks: tasks}, context) when is_list(tasks) do
    state = context.agent_state
    worker_count = length(state.worker_ids)

    {submitted, directives, next_worker} =
      Enum.reduce(tasks, {state.submitted, [], state.next_worker}, fn task,
                                                                      {submitted, directives,
                                                                       next_worker} ->
        target_id = Enum.at(state.worker_ids, rem(next_worker, worker_count))
        signal = Signals.work_requested(state.group_id, state.generation, target_id, task)

        assignment = %{worker_id: target_id, value: task.value}

        {
          Map.put(submitted, task.id, assignment),
          [Directive.emit(signal, @dispatch) | directives],
          next_worker + 1
        }
      end)

    next_state = %{
      state
      | submitted: submitted,
        next_worker: rem(next_worker, worker_count)
    }

    {:ok, next_state, Enum.reverse(directives)}
  end
end

defmodule Jido.Examples.Applications.FixedGroup.RecordResult do
  use Jido.Action, name: "fixed_group_record_result"

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    if input.group_id == state.group_id and input.generation == state.generation do
      result = %{worker_id: input.worker_id, result: input.result}
      {:ok, %{state | results: Map.put_new(state.results, input.task_id, result)}}
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.FixedGroup.ControllerAgent do
  use Jido.Agent, name: "fixed_group_controller"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             desired: Zoi.map() |> Zoi.default(%{}),
             worker_ids: Zoi.list(Zoi.string()) |> Zoi.default([]),
             environment_id: Zoi.string() |> Zoi.default(""),
             ready_members: Zoi.list(Zoi.string()) |> Zoi.default([]),
             member_starts: Zoi.map() |> Zoi.default(%{}),
             next_worker: Zoi.integer() |> Zoi.default(0),
             submitted: Zoi.map() |> Zoi.default(%{}),
             results: Zoi.map() |> Zoi.default(%{})
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :fixed_group_bus, paths: ["fixed.work.applied"]]
  end

  routes do
    route "fixed.group.start", Jido.Examples.Applications.FixedGroup.Start
    route "jido.agent.child.started", Jido.Examples.Applications.FixedGroup.RecordMemberReady
    route "fixed.work.submit", Jido.Examples.Applications.FixedGroup.Submit
    route "fixed.work.applied", Jido.Examples.Applications.FixedGroup.RecordResult
  end
end
