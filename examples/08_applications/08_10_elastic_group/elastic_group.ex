defmodule Jido.Examples.Applications.ElasticGroup.Signals do
  alias Jido.Signal

  def work_requested(group_id, generation, target_id, task) do
    Signal.new!(
      "elastic.work.requested",
      %{
        group_id: group_id,
        generation: generation,
        target_id: target_id,
        task_id: task.id,
        attempt: task.attempt,
        value: task.value,
        delay_ms: Map.get(task, :delay_ms, 20)
      },
      source: "/elastic/controller"
    )
  end

  def worker_finish(data) do
    Signal.new!("elastic.worker.finish", data, source: "/elastic/worker/clock")
  end

  def drain_requested(group_id, generation, target_id) do
    Signal.new!(
      "elastic.worker.drain",
      %{group_id: group_id, generation: generation, target_id: target_id},
      source: "/elastic/controller"
    )
  end

  def environment_apply(group_id, generation, worker_id, task_id, result, attempt \\ 1) do
    Signal.new!(
      "elastic.environment.apply",
      %{
        group_id: group_id,
        generation: generation,
        worker_id: worker_id,
        task_id: task_id,
        attempt: attempt,
        result: result
      },
      source: "/elastic/worker/#{worker_id}"
    )
  end

  def work_completed(data) do
    Signal.new!("elastic.work.completed", data, source: "/elastic/environment")
  end

  def control(status, group_id, generation, member_id, extra \\ %{}) do
    Signal.new!(
      "elastic.control.#{status}",
      Map.merge(
        %{group_id: group_id, generation: generation, member_id: member_id},
        extra
      ),
      source: "/elastic/control"
    )
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.Work do
  use Jido.Action, name: "elastic_group_work"

  alias Jido.Agent.Directive
  alias Jido.Plugin.Scheduler
  alias Jido.Examples.Applications.ElasticGroup.Signals

  @dispatch {:bus, [target: :elastic_group_bus]}

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    cond do
      input.group_id != state.group_id or input.generation != state.generation or
          input.target_id != state.member_id ->
        {:ok, %{state | ignored: state.ignored + 1}}

      input.attempt <= Map.get(state.attempts, input.task_id, 0) ->
        {:ok, %{state | ignored: state.ignored + 1}}

      state.phase != :ready and Map.get(state.current_task, :id) != input.task_id ->
        {:ok, %{state | ignored: state.ignored + 1}}

      true ->
        task = %{
          id: input.task_id,
          value: input.value,
          delay_ms: input.delay_ms,
          attempt: input.attempt
        }

        next_state = %{
          state
          | phase: :busy,
            current_task: task,
            attempts: Map.put(state.attempts, input.task_id, input.attempt)
        }

        busy =
          Signals.control("worker.busy", state.group_id, state.generation, state.member_id, %{
            task_id: input.task_id
          })

        finish =
          Signals.worker_finish(%{
            group_id: state.group_id,
            generation: state.generation,
            worker_id: state.member_id,
            task_id: input.task_id,
            attempt: input.attempt,
            value: input.value
          })

        {:ok, next_state,
         [
           Directive.emit(busy, @dispatch),
           Scheduler.schedule(input.delay_ms, finish)
         ]}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.FinishWork do
  use Jido.Action, name: "elastic_group_finish_work"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.Signals

  @dispatch {:bus, [target: :elastic_group_bus]}

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    if current_task?(state, input) do
      result = input.value * 3

      apply_result =
        Signals.environment_apply(
          state.group_id,
          state.generation,
          state.member_id,
          input.task_id,
          result,
          input.attempt
        )

      {phase, status} =
        if state.phase == :draining,
          do: {:drained, "worker.drained"},
          else: {:ready, "worker.ready"}

      status_signal =
        Signals.control(status, state.group_id, state.generation, state.member_id, %{
          task_id: input.task_id
        })

      next_state = %{
        state
        | phase: phase,
          current_task: %{},
          handled: state.handled ++ [input.task_id]
      }

      {:ok, next_state,
       [Directive.emit(apply_result, @dispatch), Directive.emit(status_signal, @dispatch)]}
    else
      {:ok, %{state | ignored: state.ignored + 1}}
    end
  end

  defp current_task?(state, input) do
    state.phase in [:busy, :draining] and
      state.group_id == input.group_id and
      state.generation == input.generation and
      state.member_id == input.worker_id and
      Map.get(state.current_task, :id) == input.task_id and
      Map.get(state.current_task, :attempt) == input.attempt
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.DrainWorker do
  use Jido.Action, name: "elastic_group_drain_worker"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.Signals

  @dispatch {:bus, [target: :elastic_group_bus]}

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    if input.group_id == state.group_id and input.generation == state.generation and
         input.target_id == state.member_id do
      if state.current_task == %{} do
        drained =
          Signals.control("worker.drained", state.group_id, state.generation, state.member_id)

        {:ok, %{state | phase: :drained}, [Directive.emit(drained, @dispatch)]}
      else
        draining =
          Signals.control("worker.draining", state.group_id, state.generation, state.member_id, %{
            task_id: state.current_task.id
          })

        {:ok, %{state | phase: :draining}, [Directive.emit(draining, @dispatch)]}
      end
    else
      {:ok, %{state | ignored: state.ignored + 1}}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.WorkerAgent do
  use Jido.Agent, name: "elastic_group_worker"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             member_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             phase: Zoi.enum([:ready, :busy, :draining, :drained]) |> Zoi.default(:ready),
             current_task: Zoi.map() |> Zoi.default(%{}),
             attempts: Zoi.map() |> Zoi.default(%{}),
             handled: Zoi.list(Zoi.string()) |> Zoi.default([]),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :elastic_group_bus, paths: ["elastic.work.requested", "elastic.worker.drain"]]

    plugin Jido.Plugin.Scheduler
  end

  routes do
    route "elastic.work.requested", Jido.Examples.Applications.ElasticGroup.Work
    route "elastic.worker.finish", Jido.Examples.Applications.ElasticGroup.FinishWork
    route "elastic.worker.drain", Jido.Examples.Applications.ElasticGroup.DrainWorker
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.ApplyResult do
  use Jido.Action, name: "elastic_group_apply_result"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.Signals

  @dispatch {:bus, [target: :elastic_group_bus]}

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
          attempt: input.attempt,
          result: input.result
        }

        next_state = %{state | results: Map.put(state.results, input.task_id, result)}

        completed =
          Signals.work_completed(%{
            group_id: state.group_id,
            generation: state.generation,
            task_id: input.task_id,
            worker_id: input.worker_id,
            attempt: input.attempt,
            result: input.result
          })

        {:ok, next_state, [Directive.emit(completed, @dispatch)]}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.EnvironmentAgent do
  use Jido.Agent, name: "elastic_group_environment"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             results: Zoi.map() |> Zoi.default(%{}),
             duplicates: Zoi.integer() |> Zoi.default(0),
             ignored: Zoi.integer() |> Zoi.default(0)
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :elastic_group_bus, paths: ["elastic.environment.apply"]]
  end

  routes do
    route "elastic.environment.apply", Jido.Examples.Applications.ElasticGroup.ApplyResult
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.RecordControl do
  use Jido.Action, name: "elastic_group_record_control"

  @impl Jido.Action
  def run(_input, context) do
    state = context.agent_state
    type = context.signal.type

    {:ok,
     %{
       state
       | events: state.events ++ [type],
         counts: Map.update(state.counts, type, 1, &(&1 + 1))
     }}
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.MonitorAgent do
  use Jido.Agent, name: "elastic_group_monitor"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             events: Zoi.list(Zoi.string()) |> Zoi.default([]),
             counts: Zoi.map() |> Zoi.default(%{})
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [bus: :elastic_group_bus, paths: ["elastic.control.**"]]
  end

  routes do
    route "elastic.control.**", Jido.Examples.Applications.ElasticGroup.RecordControl
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.ControllerLogic do
  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.{Signals, WorkerAgent}

  @dispatch {:bus, [target: :elastic_group_bus]}

  def spawn_worker(group_id, generation, index) do
    worker_id = worker_id(group_id, index)

    Directive.spawn_agent(WorkerAgent, worker_tag(index),
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
  end

  # Keep an interrupted assignment with its worker. Restart retries the saved
  # input with a new attempt before that worker can accept another task.
  def recover_worker(state, worker_id) do
    case Enum.find(state.in_flight, fn {_id, assignment} -> assignment.worker_id == worker_id end) do
      nil ->
        {%{state | worker_status: Map.put(state.worker_status, worker_id, :ready)}, []}

      {task_id, assignment} ->
        task = assignment.task

        task = %{
          task
          | attempt: task.attempt + 1,
            delay_ms: Map.get(task, :retry_delay_ms, task.delay_ms)
        }

        assignment = %{assignment | task: task}

        state = %{
          state
          | in_flight: Map.put(state.in_flight, task_id, assignment),
            worker_status: Map.put(state.worker_status, worker_id, :busy)
        }

        signal = Signals.work_requested(state.group_id, state.generation, worker_id, task)
        {state, [emit(signal)]}
    end
  end

  def worker_id(group_id, index), do: "#{group_id}/worker-#{index}"
  def worker_tag(index), do: "worker-#{index}"

  def emit(signal), do: Directive.emit(signal, @dispatch)

  def dispatch_available(state) do
    available =
      Enum.filter(state.desired_workers, fn worker_id ->
        Map.get(state.worker_status, worker_id) == :ready
      end)

    count = min(length(available), length(state.queue))
    {selected_workers, _unused_workers} = Enum.split(available, count)
    {selected_tasks, remaining_queue} = Enum.split(state.queue, count)

    {next_state, directives} =
      Enum.zip(selected_workers, selected_tasks)
      |> Enum.reduce({%{state | queue: remaining_queue}, []}, fn {worker_id, task},
                                                                 {state, directives} ->
        task = Map.update(task, :attempt, 1, &(&1 + 1))

        signal =
          Signals.work_requested(state.group_id, state.generation, worker_id, task)

        assignment = %{worker_id: worker_id, task: task}

        next_state = %{
          state
          | worker_status: Map.put(state.worker_status, worker_id, :busy),
            in_flight: Map.put(state.in_flight, task.id, assignment)
        }

        {next_state, [emit(signal) | directives]}
      end)

    {next_state, Enum.reverse(directives)}
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.Start do
  use Jido.Action, name: "elastic_group_start"

  alias Jido.Agent.Directive

  alias Jido.Examples.Applications.ElasticGroup.{
    ControllerLogic,
    EnvironmentAgent,
    MonitorAgent
  }

  @impl Jido.Action
  def run(%{group_id: group_id, min_workers: min_workers, max_workers: max_workers}, context) do
    state = context.agent_state
    generation = state.generation + 1
    environment_id = "#{group_id}/environment"
    monitor_id = "#{group_id}/monitor"
    indexes = Enum.to_list(1..min_workers)
    worker_ids = Enum.map(indexes, &ControllerLogic.worker_id(group_id, &1))
    worker_indexes = Map.new(Enum.zip(worker_ids, indexes))

    environment =
      Directive.spawn_agent(EnvironmentAgent, :environment,
        opts: %{
          id: environment_id,
          initial_state: %{group_id: group_id, generation: generation}
        },
        meta: %{role: "environment"},
        restart: :transient
      )

    monitor =
      Directive.spawn_agent(MonitorAgent, :monitor,
        opts: %{
          id: monitor_id,
          initial_state: %{group_id: group_id, generation: generation}
        },
        meta: %{role: "monitor"},
        restart: :transient
      )

    workers = Enum.map(indexes, &ControllerLogic.spawn_worker(group_id, generation, &1))

    next_state = %{
      state
      | group_id: group_id,
        generation: generation,
        min_workers: min_workers,
        max_workers: max_workers,
        next_worker_index: min_workers + 1,
        desired_workers: worker_ids,
        worker_indexes: worker_indexes,
        worker_status: Map.new(worker_ids, &{&1, :starting}),
        draining_workers: [],
        queue: [],
        in_flight: %{},
        results: %{},
        low_observations: 0,
        persistent_members: [environment_id, monitor_id],
        member_starts: %{},
        exits: []
    }

    {:ok, next_state, [environment, monitor | workers]}
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.RecordMemberStarted do
  use Jido.Action, name: "elastic_group_record_member_started"

  alias Jido.Examples.Applications.ElasticGroup.{ControllerLogic, Signals}

  @impl Jido.Action
  def run(%{child_id: child_id, meta: meta}, context) do
    state = context.agent_state
    starts = Map.update(state.member_starts, child_id, 1, &(&1 + 1))
    state = %{state | member_starts: starts}
    role = Map.get(meta, :role, "unknown")

    ready =
      Signals.control("member.ready", state.group_id, state.generation, child_id, %{
        role: role,
        restarted: Map.get(meta, :restarted, false)
      })

    if role == "worker" do
      if child_id in state.draining_workers do
        next_state = %{state | worker_status: Map.put(state.worker_status, child_id, :draining)}
        drain = Signals.drain_requested(state.group_id, state.generation, child_id)
        {:ok, next_state, [ControllerLogic.emit(ready), ControllerLogic.emit(drain)]}
      else
        {state, recovery} = ControllerLogic.recover_worker(state, child_id)
        {next_state, available} = ControllerLogic.dispatch_available(state)
        work = recovery ++ available
        {:ok, next_state, [ControllerLogic.emit(ready) | work]}
      end
    else
      {:ok, state, [ControllerLogic.emit(ready)]}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.Enqueue do
  use Jido.Action, name: "elastic_group_enqueue"

  alias Jido.Examples.Applications.ElasticGroup.ControllerLogic

  @impl Jido.Action
  def run(%{tasks: tasks}, context) when is_list(tasks) do
    state = context.agent_state
    state = %{state | queue: state.queue ++ tasks, low_observations: 0}
    demand = length(state.queue) + map_size(state.in_flight)
    {state, spawn_directives} = maybe_scale_up(state, demand)
    {state, work_directives} = ControllerLogic.dispatch_available(state)
    {:ok, state, spawn_directives ++ work_directives}
  end

  defp maybe_scale_up(state, demand)
       when demand >= 4 and length(state.desired_workers) < state.max_workers do
    count = state.max_workers - length(state.desired_workers)
    indexes = Enum.to_list(state.next_worker_index..(state.next_worker_index + count - 1))
    worker_ids = Enum.map(indexes, &ControllerLogic.worker_id(state.group_id, &1))

    worker_indexes =
      Enum.zip(worker_ids, indexes)
      |> Enum.reduce(state.worker_indexes, fn {worker_id, index}, acc ->
        Map.put(acc, worker_id, index)
      end)

    worker_status =
      Enum.reduce(worker_ids, state.worker_status, &Map.put(&2, &1, :starting))

    next_state = %{
      state
      | desired_workers: state.desired_workers ++ worker_ids,
        worker_indexes: worker_indexes,
        worker_status: worker_status,
        next_worker_index: state.next_worker_index + count
    }

    directives =
      Enum.map(indexes, &ControllerLogic.spawn_worker(state.group_id, state.generation, &1))

    {next_state, directives}
  end

  defp maybe_scale_up(state, _demand), do: {state, []}
end

defmodule Jido.Examples.Applications.ElasticGroup.RecordCompletion do
  use Jido.Action, name: "elastic_group_record_completion"

  alias Jido.Examples.Applications.ElasticGroup.ControllerLogic

  @impl Jido.Action
  def run(input, context) do
    state = context.agent_state

    case Map.get(state.in_flight, input.task_id) do
      %{worker_id: worker_id, task: %{attempt: attempt}}
      when worker_id == input.worker_id and attempt == input.attempt ->
        result = %{worker_id: input.worker_id, attempt: input.attempt, result: input.result}

        status =
          if input.worker_id in state.draining_workers, do: :draining, else: :ready

        state = %{
          state
          | results: Map.put_new(state.results, input.task_id, result),
            in_flight: Map.delete(state.in_flight, input.task_id),
            worker_status: Map.put(state.worker_status, input.worker_id, status)
        }

        {next_state, directives} = ControllerLogic.dispatch_available(state)
        {:ok, next_state, directives}

      _assignment ->
        {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.RecordChildExit do
  use Jido.Action, name: "elastic_group_record_child_exit"

  alias Jido.Examples.Applications.ElasticGroup.{ControllerLogic, Signals}

  @impl Jido.Action
  def run(%{child_id: child_id, reason: reason}, context) do
    state = context.agent_state

    if Map.has_key?(state.worker_indexes, child_id) do
      lost_tasks =
        state.in_flight
        |> Map.values()
        |> Enum.filter(&(&1.worker_id == child_id))
        |> Enum.map(& &1.task)

      desired? = child_id in state.desired_workers

      status =
        if desired?,
          do: Map.put(state.worker_status, child_id, :starting),
          else: Map.delete(state.worker_status, child_id)

      next_state = %{
        state
        | worker_status: status,
          exits: state.exits ++ [%{member_id: child_id, reason: reason}]
      }

      if desired? do
        failed =
          Signals.control("worker.failed", state.group_id, state.generation, child_id, %{
            reason: reason,
            reclaimed_tasks: Enum.map(lost_tasks, & &1.id)
          })

        {:ok, next_state, [ControllerLogic.emit(failed)]}
      else
        {:ok, next_state}
      end
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.ObserveScale do
  use Jido.Action, name: "elastic_group_observe_scale"

  alias Jido.Examples.Applications.ElasticGroup.{ControllerLogic, Signals}

  @impl Jido.Action
  def run(_input, context) do
    state = context.agent_state
    idle? = state.queue == [] and state.in_flight == %{}

    cond do
      not idle? ->
        {:ok, %{state | low_observations: 0}}

      length(state.desired_workers) <= state.min_workers ->
        {:ok, %{state | low_observations: 0}}

      state.low_observations + 1 < state.scale_down_observations ->
        {:ok, %{state | low_observations: state.low_observations + 1}}

      true ->
        {kept, draining} = Enum.split(state.desired_workers, state.min_workers)

        worker_status =
          Enum.reduce(draining, state.worker_status, &Map.put(&2, &1, :draining))

        next_state = %{
          state
          | desired_workers: kept,
            draining_workers: draining,
            worker_status: worker_status,
            low_observations: 0
        }

        directives =
          Enum.map(draining, fn worker_id ->
            state.group_id
            |> Signals.drain_requested(state.generation, worker_id)
            |> ControllerLogic.emit()
          end)

        {:ok, next_state, directives}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.RecordDrained do
  use Jido.Action, name: "elastic_group_record_drained"

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.ControllerLogic

  @impl Jido.Action
  def run(%{group_id: group_id, generation: generation, member_id: member_id}, context) do
    state = context.agent_state

    if group_id == state.group_id and generation == state.generation and
         member_id in state.draining_workers do
      index = Map.fetch!(state.worker_indexes, member_id)

      next_state = %{
        state
        | draining_workers: List.delete(state.draining_workers, member_id),
          worker_status: Map.delete(state.worker_status, member_id)
      }

      {:ok, next_state, [Directive.stop_child(ControllerLogic.worker_tag(index))]}
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.ControllerAgent do
  use Jido.Agent, name: "elastic_group_controller"

  agent do
    schema Zoi.object(%{
             group_id: Zoi.string() |> Zoi.default(""),
             generation: Zoi.integer() |> Zoi.default(0),
             min_workers: Zoi.integer() |> Zoi.default(2),
             max_workers: Zoi.integer() |> Zoi.default(5),
             next_worker_index: Zoi.integer() |> Zoi.default(1),
             desired_workers: Zoi.list(Zoi.string()) |> Zoi.default([]),
             worker_indexes: Zoi.map() |> Zoi.default(%{}),
             worker_status: Zoi.map() |> Zoi.default(%{}),
             draining_workers: Zoi.list(Zoi.string()) |> Zoi.default([]),
             queue: Zoi.list(Zoi.map()) |> Zoi.default([]),
             in_flight: Zoi.map() |> Zoi.default(%{}),
             results: Zoi.map() |> Zoi.default(%{}),
             low_observations: Zoi.integer() |> Zoi.default(0),
             scale_down_observations: Zoi.integer() |> Zoi.default(2),
             persistent_members: Zoi.list(Zoi.string()) |> Zoi.default([]),
             member_starts: Zoi.map() |> Zoi.default(%{}),
             exits: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Examples.Applications.BusInput,
      config: [
        bus: :elastic_group_bus,
        paths: ["elastic.work.completed", "elastic.control.worker.drained"]
      ]
  end

  routes do
    route "elastic.group.start", Jido.Examples.Applications.ElasticGroup.Start
    route "jido.agent.child.started", Jido.Examples.Applications.ElasticGroup.RecordMemberStarted
    route "jido.agent.child.exit", Jido.Examples.Applications.ElasticGroup.RecordChildExit
    route "elastic.tasks.enqueue", Jido.Examples.Applications.ElasticGroup.Enqueue
    route "elastic.work.completed", Jido.Examples.Applications.ElasticGroup.RecordCompletion
    route "elastic.scale.observe", Jido.Examples.Applications.ElasticGroup.ObserveScale
    route "elastic.control.worker.drained", Jido.Examples.Applications.ElasticGroup.RecordDrained
  end
end
