defmodule Jido.Examples.Applications.PurposeLoop.Agent do
  @moduledoc "Runs bounded scheduled work and supports pause, resume, and drain controls."
  use Jido.Agent, name: "application_purpose_loop_agent"

  alias Jido.Examples.Applications.PurposeLoop.State

  agent do
    schema Zoi.object(%{
             purpose: Zoi.string() |> Zoi.default(""),
             phase:
               Zoi.enum([:new, :running, :idle, :paused, :draining, :drained, :exhausted])
               |> Zoi.default(:new),
             generation: Zoi.integer() |> Zoi.default(0),
             next_sequence: Zoi.integer() |> Zoi.default(0),
             remaining: Zoi.list(Zoi.string()) |> Zoi.default([]),
             completed: Zoi.list(Zoi.string()) |> Zoi.default([]),
             last_completed: Zoi.string() |> Zoi.default(""),
             budget: Zoi.integer() |> Zoi.default(0),
             budget_remaining: Zoi.integer() |> Zoi.default(0),
             turns: Zoi.integer() |> Zoi.default(0),
             idle_ticks: Zoi.integer() |> Zoi.default(0),
             ignored_ticks: Zoi.integer() |> Zoi.default(0),
             rejected_work: Zoi.integer() |> Zoi.default(0),
             work_delay_ms: Zoi.integer() |> Zoi.default(20),
             idle_delay_ms: Zoi.integer() |> Zoi.default(100)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/applications/purpose_loop"

    route "examples.applications.purpose_loop.start" do
      action input,
        schema:
          Zoi.object(%{
            purpose: Zoi.string() |> Zoi.min(1),
            work: Zoi.list(Zoi.string()),
            work_delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
            idle_delay_ms: Zoi.integer() |> Zoi.min(0) |> Zoi.optional(),
            budget: Zoi.integer() |> Zoi.min(0) |> Zoi.optional()
          }),
        context: context do
        State.start(input, context.agent_state)
      end
    end

    route "examples.applications.purpose_loop.tick" do
      action input,
        schema: Zoi.object(%{generation: Zoi.integer(), sequence: Zoi.integer()}),
        context: context do
        State.tick(input, context.agent_state)
      end
    end

    route "examples.applications.purpose_loop.enqueue" do
      action input,
        schema: Zoi.object(%{work: Zoi.list(Zoi.string())}),
        context: context do
        State.enqueue(input, context.agent_state)
      end
    end

    route "examples.applications.purpose_loop.pause" do
      action _input, context: context do
        State.pause(context.agent_state)
      end
    end

    route "examples.applications.purpose_loop.resume" do
      action _input, context: context do
        State.resume(context.agent_state)
      end
    end

    route "examples.applications.purpose_loop.drain" do
      action _input, context: context do
        State.drain(context.agent_state)
      end
    end
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.State do
  @moduledoc false

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @active_phases [:running, :draining]

  def start(input, state) do
    work = input.work
    work_delay_ms = Map.get(input, :work_delay_ms, 20)
    idle_delay_ms = Map.get(input, :idle_delay_ms, 100)
    budget = Map.get(input, :budget, length(work))
    phase = if work == [], do: :idle, else: :running

    next_state = %{
      state
      | purpose: input.purpose,
        phase: phase,
        generation: state.generation + 1,
        next_sequence: 1,
        remaining: work,
        completed: [],
        last_completed: "",
        budget: budget,
        budget_remaining: budget,
        work_delay_ms: work_delay_ms,
        idle_delay_ms: idle_delay_ms
    }

    delay_ms = if phase == :idle, do: idle_delay_ms, else: work_delay_ms
    {:ok, next_state, [Clock.schedule_tick(next_state, delay_ms)]}
  end

  def tick(%{generation: generation, sequence: sequence}, state) do
    if current_tick?(state, generation, sequence) do
      advance(state)
    else
      {:ok, %{state | ignored_ticks: state.ignored_ticks + 1}}
    end
  end

  def enqueue(%{work: []}, state), do: {:ok, state}

  def enqueue(%{work: work}, %{phase: phase} = state) when phase in [:draining, :drained] do
    {:ok, %{state | rejected_work: state.rejected_work + length(work)}}
  end

  def enqueue(%{work: work}, %{phase: :paused} = state) do
    added_budget = length(work)

    {:ok,
     %{
       state
       | remaining: state.remaining ++ work,
         budget: state.budget + added_budget,
         budget_remaining: state.budget_remaining + added_budget
     }}
  end

  def enqueue(%{work: work}, state) do
    added_budget = length(work)

    next_state = %{
      state
      | phase: :running,
        generation: state.generation + 1,
        next_sequence: 1,
        remaining: state.remaining ++ work,
        budget: state.budget + added_budget,
        budget_remaining: state.budget_remaining + added_budget
    }

    {:ok, next_state, [Clock.schedule_tick(next_state, 0)]}
  end

  def pause(%{phase: phase} = state) when phase in [:running, :idle] do
    {:ok, %{state | phase: :paused, generation: state.generation + 1, next_sequence: 1}}
  end

  def pause(state), do: {:ok, state}

  def resume(%{phase: :paused} = state) do
    phase = if state.remaining == [], do: :idle, else: :running

    next_state = %{
      state
      | phase: phase,
        generation: state.generation + 1,
        next_sequence: 1
    }

    {:ok, next_state, [Clock.schedule_tick(next_state, 0)]}
  end

  def resume(state), do: {:ok, state}

  def drain(%{phase: phase} = state) when phase in [:draining, :drained], do: {:ok, state}

  def drain(%{remaining: []} = state) do
    {:ok, %{state | phase: :drained, generation: state.generation + 1, next_sequence: 1}}
  end

  def drain(state) do
    next_state = %{
      state
      | phase: :draining,
        generation: state.generation + 1,
        next_sequence: 1
    }

    {:ok, next_state, [Clock.schedule_tick(next_state, 0)]}
  end

  defp current_tick?(state, generation, sequence) do
    state.phase in [:running, :idle, :draining] and
      state.generation == generation and
      state.next_sequence == sequence
  end

  defp advance(
         %{phase: phase, remaining: [unit | remaining], budget_remaining: budget_remaining} =
           state
       )
       when phase in @active_phases and budget_remaining > 0 do
    next_state = %{
      state
      | remaining: remaining,
        completed: state.completed ++ [unit],
        last_completed: unit,
        budget_remaining: state.budget_remaining - 1,
        turns: state.turns + 1,
        next_sequence: state.next_sequence + 1
    }

    next_after_work(next_state, phase)
  end

  defp advance(%{phase: :running, remaining: []} = state) do
    state
    |> record_idle_turn()
    |> schedule_idle_turn()
  end

  defp advance(%{phase: :idle} = state) do
    state
    |> record_idle_turn()
    |> schedule_idle_turn()
  end

  defp advance(%{phase: :draining, remaining: []} = state) do
    {:ok, %{state | phase: :drained, turns: state.turns + 1}}
  end

  defp advance(%{phase: phase, remaining: [_unit | _remaining]} = state)
       when phase in @active_phases do
    {:ok, %{state | phase: :exhausted, turns: state.turns + 1}}
  end

  defp next_after_work(%{remaining: []} = state, :draining),
    do: {:ok, %{state | phase: :drained}}

  defp next_after_work(%{remaining: []} = state, :running) do
    next_state = %{state | phase: :idle}
    {:ok, next_state, [Clock.schedule_tick(next_state, next_state.idle_delay_ms)]}
  end

  defp next_after_work(state, _phase),
    do: {:ok, state, [Clock.schedule_tick(state, state.work_delay_ms)]}

  defp record_idle_turn(state) do
    %{
      state
      | phase: :idle,
        turns: state.turns + 1,
        idle_ticks: state.idle_ticks + 1,
        next_sequence: state.next_sequence + 1
    }
  end

  defp schedule_idle_turn(state),
    do: {:ok, state, [Clock.schedule_tick(state, state.idle_delay_ms)]}
end
