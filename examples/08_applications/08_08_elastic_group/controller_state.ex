defmodule Jido.Examples.Applications.ElasticGroup.ControllerState do
  @moduledoc false

  alias Jido.Agent.Directive

  alias Jido.Examples.Applications.ElasticGroup.{
    EnvironmentAgent,
    MonitorAgent,
    Signals,
    WorkerAgent
  }

  @dispatch {:bus, [target: :elastic_group_bus]}

  def start(%{group_id: group_id, min_workers: min_workers, max_workers: max_workers}, state) do
    generation = state.generation + 1
    environment_id = "#{group_id}/environment"
    monitor_id = "#{group_id}/monitor"
    indexes = Enum.to_list(1..min_workers)
    worker_ids = Enum.map(indexes, &worker_id(group_id, &1))
    worker_indexes = Map.new(Enum.zip(worker_ids, indexes))

    environment =
      Directive.spawn_child(EnvironmentAgent, :environment,
        opts: %{
          id: environment_id,
          initial_state: %{group_id: group_id, generation: generation}
        },
        meta: %{role: "environment"},
        restart: :transient
      )

    monitor =
      Directive.spawn_child(MonitorAgent, :monitor,
        opts: %{
          id: monitor_id,
          initial_state: %{group_id: group_id, generation: generation}
        },
        meta: %{role: "monitor"},
        restart: :transient
      )

    workers = Enum.map(indexes, &spawn_worker(group_id, generation, &1))

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

  def member_started(%{child_id: child_id, meta: meta}, state) do
    starts = Map.update(state.member_starts, child_id, 1, &(&1 + 1))
    state = %{state | member_starts: starts}
    role = Map.get(meta, :role, "unknown")

    ready =
      Signals.control("member.ready", state.group_id, state.generation, child_id, %{
        role: role,
        restarted: Map.get(meta, :restarted, false)
      })

    case {role, child_id in state.draining_workers} do
      {"worker", true} ->
        next_state = %{state | worker_status: Map.put(state.worker_status, child_id, :draining)}
        drain = Signals.drain_requested(state.group_id, state.generation, child_id)
        {:ok, next_state, [emit(ready), emit(drain)]}

      {"worker", false} ->
        {recovered_state, recovery} = recover_worker(state, child_id)
        {next_state, available} = dispatch_available(recovered_state)
        {:ok, next_state, [emit(ready) | recovery ++ available]}

      {_role, _draining?} ->
        {:ok, state, [emit(ready)]}
    end
  end

  def enqueue(%{tasks: tasks}, state) do
    state = %{state | queue: state.queue ++ tasks, low_observations: 0}
    demand = length(state.queue) + map_size(state.in_flight)
    {state, spawn_directives} = maybe_scale_up(state, demand)
    {state, work_directives} = dispatch_available(state)
    {:ok, state, spawn_directives ++ work_directives}
  end

  def record_completion(input, state) do
    case Map.get(state.in_flight, input.task_id) do
      %{worker_id: worker_id, task: %{attempt: attempt}}
      when worker_id == input.worker_id and attempt == input.attempt ->
        result = %{worker_id: input.worker_id, attempt: input.attempt, result: input.result}
        status = if input.worker_id in state.draining_workers, do: :draining, else: :ready

        state = %{
          state
          | results: Map.put_new(state.results, input.task_id, result),
            in_flight: Map.delete(state.in_flight, input.task_id),
            worker_status: Map.put(state.worker_status, input.worker_id, status)
        }

        {next_state, directives} = dispatch_available(state)
        {:ok, next_state, directives}

      _assignment ->
        {:ok, state}
    end
  end

  def child_exit(%{child_id: child_id, reason: reason}, state) do
    if Map.has_key?(state.worker_indexes, child_id) do
      lost_tasks =
        state.in_flight
        |> Map.values()
        |> Enum.filter(&(&1.worker_id == child_id))
        |> Enum.map(& &1.task)

      desired? = child_id in state.desired_workers

      worker_status =
        if desired?,
          do: Map.put(state.worker_status, child_id, :starting),
          else: Map.delete(state.worker_status, child_id)

      next_state = %{
        state
        | worker_status: worker_status,
          exits: state.exits ++ [%{member_id: child_id, reason: reason}]
      }

      if desired? do
        failed =
          Signals.control("worker.failed", state.group_id, state.generation, child_id, %{
            reason: reason,
            reclaimed_tasks: Enum.map(lost_tasks, & &1.id)
          })

        {:ok, next_state, [emit(failed)]}
      else
        {:ok, next_state}
      end
    else
      {:ok, state}
    end
  end

  def observe_scale(state) do
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
            |> emit()
          end)

        {:ok, next_state, directives}
    end
  end

  def record_drained(%{group_id: group_id, generation: generation, member_id: member_id}, state) do
    if group_id == state.group_id and generation == state.generation and
         member_id in state.draining_workers do
      index = Map.fetch!(state.worker_indexes, member_id)

      next_state = %{
        state
        | draining_workers: List.delete(state.draining_workers, member_id),
          worker_status: Map.delete(state.worker_status, member_id)
      }

      {:ok, next_state, [Directive.stop_child(worker_tag(index))]}
    else
      {:ok, state}
    end
  end

  defp maybe_scale_up(state, demand)
       when demand >= 4 and length(state.desired_workers) < state.max_workers do
    count = state.max_workers - length(state.desired_workers)
    indexes = Enum.to_list(state.next_worker_index..(state.next_worker_index + count - 1))
    worker_ids = Enum.map(indexes, &worker_id(state.group_id, &1))

    worker_indexes =
      Enum.zip(worker_ids, indexes)
      |> Enum.reduce(state.worker_indexes, fn {worker_id, index}, acc ->
        Map.put(acc, worker_id, index)
      end)

    worker_status = Enum.reduce(worker_ids, state.worker_status, &Map.put(&2, &1, :starting))

    next_state = %{
      state
      | desired_workers: state.desired_workers ++ worker_ids,
        worker_indexes: worker_indexes,
        worker_status: worker_status,
        next_worker_index: state.next_worker_index + count
    }

    directives = Enum.map(indexes, &spawn_worker(state.group_id, state.generation, &1))
    {next_state, directives}
  end

  defp maybe_scale_up(state, _demand), do: {state, []}

  defp recover_worker(state, worker_id) do
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

  defp dispatch_available(state) do
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
        signal = Signals.work_requested(state.group_id, state.generation, worker_id, task)
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

  defp spawn_worker(group_id, generation, index) do
    worker_id = worker_id(group_id, index)

    Directive.spawn_child(WorkerAgent, worker_tag(index),
      opts: %{
        id: worker_id,
        initial_state: %{group_id: group_id, member_id: worker_id, generation: generation}
      },
      meta: %{role: "worker", index: index},
      restart: :transient
    )
  end

  defp worker_id(group_id, index), do: "#{group_id}/worker-#{index}"
  defp worker_tag(index), do: "worker-#{index}"
  defp emit(signal), do: Directive.emit(signal, @dispatch)
end
