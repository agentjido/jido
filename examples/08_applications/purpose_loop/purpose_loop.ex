defmodule Jido.Examples.Applications.PurposeLoop.Signals do
  alias Jido.Signal

  def tick(generation, sequence) do
    Signal.new!(
      "purpose.tick",
      %{generation: generation, sequence: sequence},
      source: "/purpose/clock"
    )
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Clock do
  alias Jido.Plugin.Scheduler
  alias Jido.Examples.Applications.PurposeLoop.Signals

  def schedule_tick(state, delay_ms) do
    Scheduler.schedule(delay_ms, Signals.tick(state.generation, state.next_sequence))
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Start do
  use Jido.Action, name: "purpose_loop_start"

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @impl Jido.Action
  def run(%{purpose: purpose, work: work} = input, context) when is_list(work) do
    state = context.agent_state
    work_delay_ms = Map.get(input, :work_delay_ms, 20)
    idle_delay_ms = Map.get(input, :idle_delay_ms, 100)
    budget = Map.get(input, :budget, length(work))
    phase = if work == [], do: :idle, else: :running

    next_state = %{
      state
      | purpose: purpose,
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
end

defmodule Jido.Examples.Applications.PurposeLoop.Tick do
  use Jido.Action, name: "purpose_loop_tick"

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @active_phases [:running, :draining]

  @impl Jido.Action
  def run(%{generation: generation, sequence: sequence}, context) do
    state = context.agent_state

    if current_tick?(state, generation, sequence) do
      advance(state)
    else
      {:ok, %{state | ignored_ticks: state.ignored_ticks + 1}}
    end
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

  defp next_after_work(%{remaining: []} = state, :draining) do
    {:ok, %{state | phase: :drained}}
  end

  defp next_after_work(%{remaining: []} = state, :running) do
    next_state = %{state | phase: :idle}
    {:ok, next_state, [Clock.schedule_tick(next_state, next_state.idle_delay_ms)]}
  end

  defp next_after_work(state, _phase) do
    {:ok, state, [Clock.schedule_tick(state, state.work_delay_ms)]}
  end

  defp record_idle_turn(state) do
    %{
      state
      | phase: :idle,
        turns: state.turns + 1,
        idle_ticks: state.idle_ticks + 1,
        next_sequence: state.next_sequence + 1
    }
  end

  defp schedule_idle_turn(state) do
    {:ok, state, [Clock.schedule_tick(state, state.idle_delay_ms)]}
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Enqueue do
  use Jido.Action, name: "purpose_loop_enqueue"

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @impl Jido.Action
  def run(%{work: work}, context) when is_list(work) do
    state = context.agent_state

    cond do
      work == [] ->
        {:ok, state}

      state.phase in [:draining, :drained] ->
        {:ok, %{state | rejected_work: state.rejected_work + length(work)}}

      state.phase == :paused ->
        added_budget = length(work)

        {:ok,
         %{
           state
           | remaining: state.remaining ++ work,
             budget: state.budget + added_budget,
             budget_remaining: state.budget_remaining + added_budget
         }}

      true ->
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
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Pause do
  use Jido.Action, name: "purpose_loop_pause"

  @impl Jido.Action
  def run(_input, context) do
    state = context.agent_state

    if state.phase in [:running, :idle] do
      {:ok,
       %{
         state
         | phase: :paused,
           generation: state.generation + 1,
           next_sequence: 1
       }}
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Resume do
  use Jido.Action, name: "purpose_loop_resume"

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @impl Jido.Action
  def run(_input, context) do
    state = context.agent_state

    if state.phase == :paused do
      phase = if state.remaining == [], do: :idle, else: :running

      next_state = %{
        state
        | phase: phase,
          generation: state.generation + 1,
          next_sequence: 1
      }

      {:ok, next_state, [Clock.schedule_tick(next_state, 0)]}
    else
      {:ok, state}
    end
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Drain do
  use Jido.Action, name: "purpose_loop_drain"

  alias Jido.Examples.Applications.PurposeLoop.Clock

  @impl Jido.Action
  def run(_input, context) do
    state = context.agent_state

    cond do
      state.phase in [:draining, :drained] ->
        {:ok, state}

      state.remaining == [] ->
        {:ok,
         %{
           state
           | phase: :drained,
             generation: state.generation + 1,
             next_sequence: 1
         }}

      true ->
        next_state = %{
          state
          | phase: :draining,
            generation: state.generation + 1,
            next_sequence: 1
        }

        {:ok, next_state, [Clock.schedule_tick(next_state, 0)]}
    end
  end
end

defmodule Jido.Examples.Applications.PurposeLoop.Agent do
  use Jido.Agent, name: "purpose_loop_agent"

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
    route "purpose.start", Jido.Examples.Applications.PurposeLoop.Start
    route "purpose.tick", Jido.Examples.Applications.PurposeLoop.Tick
    route "purpose.enqueue", Jido.Examples.Applications.PurposeLoop.Enqueue
    route "purpose.pause", Jido.Examples.Applications.PurposeLoop.Pause
    route "purpose.resume", Jido.Examples.Applications.PurposeLoop.Resume
    route "purpose.drain", Jido.Examples.Applications.PurposeLoop.Drain
  end
end
