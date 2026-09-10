defmodule Jido.Examples.Applications.ElasticGroup.WorkerAgent do
  @moduledoc "Runs one leased task at a time and supports a controlled drain."
  use Jido.Agent, name: "elastic_group_worker"

  alias Jido.Examples.Applications.ElasticGroup.WorkerState

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
      config: [
        bus: :elastic_group_bus,
        paths: [
          "examples.applications.elastic_group.work.requested",
          "examples.applications.elastic_group.worker.drain"
        ]
      ]

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/applications/elastic_group/worker"

    route "examples.applications.elastic_group.work.requested" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            target_id: Zoi.string(),
            task_id: Zoi.string(),
            attempt: Zoi.integer() |> Zoi.min(1),
            value: Zoi.integer(),
            delay_ms: Zoi.integer() |> Zoi.min(0)
          }),
        context: context do
        WorkerState.accept(input, context.agent_state)
      end
    end

    route "examples.applications.elastic_group.worker.finish" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            worker_id: Zoi.string(),
            task_id: Zoi.string(),
            attempt: Zoi.integer() |> Zoi.min(1),
            value: Zoi.integer()
          }),
        context: context do
        WorkerState.finish(input, context.agent_state)
      end
    end

    route "examples.applications.elastic_group.worker.drain" do
      action input,
        schema:
          Zoi.object(%{
            group_id: Zoi.string(),
            generation: Zoi.integer(),
            target_id: Zoi.string()
          }),
        context: context do
        WorkerState.drain(input, context.agent_state)
      end
    end
  end
end

defmodule Jido.Examples.Applications.ElasticGroup.WorkerState do
  @moduledoc false

  alias Jido.Agent.Directive
  alias Jido.Examples.Applications.ElasticGroup.Signals
  alias Jido.Plugin.Scheduler

  @dispatch {:bus, [target: :elastic_group_bus]}

  def accept(input, state) do
    cond do
      input.group_id != state.group_id or input.generation != state.generation or
          input.target_id != state.member_id ->
        {:ok, ignored(state)}

      input.attempt <= Map.get(state.attempts, input.task_id, 0) ->
        {:ok, ignored(state)}

      state.phase != :ready and Map.get(state.current_task, :id) != input.task_id ->
        {:ok, ignored(state)}

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
         [Directive.emit(busy, @dispatch), Scheduler.schedule(input.delay_ms, finish)]}
    end
  end

  def finish(input, state) do
    if current_task?(state, input) do
      apply_result =
        Signals.environment_apply(
          state.group_id,
          state.generation,
          state.member_id,
          input.task_id,
          input.value * 3,
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
      {:ok, ignored(state)}
    end
  end

  def drain(input, state) do
    if input.group_id == state.group_id and input.generation == state.generation and
         input.target_id == state.member_id do
      drain_current_state(state)
    else
      {:ok, ignored(state)}
    end
  end

  defp drain_current_state(%{current_task: current_task} = state) when current_task == %{} do
    drained = Signals.control("worker.drained", state.group_id, state.generation, state.member_id)
    {:ok, %{state | phase: :drained}, [Directive.emit(drained, @dispatch)]}
  end

  defp drain_current_state(state) do
    draining =
      Signals.control("worker.draining", state.group_id, state.generation, state.member_id, %{
        task_id: state.current_task.id
      })

    {:ok, %{state | phase: :draining}, [Directive.emit(draining, @dispatch)]}
  end

  defp current_task?(state, input) do
    state.phase in [:busy, :draining] and
      state.group_id == input.group_id and
      state.generation == input.generation and
      state.member_id == input.worker_id and
      Map.get(state.current_task, :id) == input.task_id and
      Map.get(state.current_task, :attempt) == input.attempt
  end

  defp ignored(state), do: %{state | ignored: state.ignored + 1}
end
