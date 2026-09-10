defmodule Jido.Examples.Applications.FixedGroup.ControllerAgent do
  @moduledoc "Owns a fixed set of persistent worker and environment Agents."
  use Jido.Agent, name: "fixed_group_controller"

  alias Jido.Examples.Applications.FixedGroup.ControllerState

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
      config: [bus: :fixed_group_bus, paths: ["examples.applications.fixed_group.work.applied"]]
  end

  routes do
    signal_source "/examples/applications/fixed_group/controller"

    route "examples.applications.fixed_group.start" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string() |> Zoi.min(1),
            worker_count: Zoi.integer() |> Zoi.min(1)
          }),
        context: context do
        ControllerState.start(input, context.agent_state)
      end

      define :start, args: [:group_id, :worker_count]
    end

    route "jido.agent.child.started" do
      action input,
        schema: Zoi.object(%{child_id: Zoi.string(), meta: Zoi.map()}),
        context: context do
        ControllerState.record_member_ready(input, context.agent_state)
      end
    end

    route "examples.applications.fixed_group.work.submit" do
      action input,
        schema:
          Zoi.object(%{
            tasks:
              Zoi.list(
                Zoi.object(%{
                  id: Zoi.string() |> Zoi.min(1),
                  value: Zoi.integer()
                })
              )
          }),
        context: context do
        ControllerState.submit(input, context.agent_state)
      end

      define :submit, args: [:tasks]
    end

    route "examples.applications.fixed_group.work.applied" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            task_id: Zoi.string(),
            worker_id: Zoi.string(),
            result: Zoi.integer()
          }),
        context: context do
        ControllerState.record_result(input, context.agent_state)
      end
    end
  end
end

defmodule Jido.Examples.Applications.FixedGroup.ControllerState do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.FixedGroup.{EnvironmentAgent, Signals, WorkerAgent}

  @dispatch {:bus, [target: :fixed_group_bus]}

  def start(%{group_id: group_id, worker_count: worker_count}, state) do
    generation = state.generation + 1
    environment_id = "#{group_id}/environment"
    worker_ids = Enum.map(1..worker_count, &"#{group_id}/worker-#{&1}")

    desired =
      Enum.reduce(worker_ids, %{environment_id => "environment"}, fn worker_id, desired ->
        Map.put(desired, worker_id, "worker")
      end)

    environment =
      Directive.spawn_child(EnvironmentAgent, :environment,
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
        Directive.spawn_child(WorkerAgent, "worker-#{index}",
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

  def record_member_ready(%{child_id: child_id, meta: meta}, state) do
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

  def submit(%{tasks: tasks}, state) do
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

  def record_result(input, state) do
    if input.group_id == state.group_id and input.generation == state.generation do
      result = %{worker_id: input.worker_id, result: input.result}
      {:ok, %{state | results: Map.put_new(state.results, input.task_id, result)}}
    else
      {:ok, state}
    end
  end
end
