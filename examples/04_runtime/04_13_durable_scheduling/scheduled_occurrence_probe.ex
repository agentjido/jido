defmodule Jido.Examples.ScheduledOccurrenceProbe.Arm do
  @moduledoc false
  use Jido.Action,
    name: "example_arm_occurrences",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), cron: Zoi.string()})

  def run(input, %{agent_state: state}) do
    generation = state.generation + 1

    tick =
      Jido.Signal.new!(
        "recovery.occurrence.tick",
        %{job_id: input.job_id, generation: generation},
        source: "/examples/schedule"
      )

    directive = Jido.Plugin.Scheduler.cron(input.job_id, input.cron, tick, generation: generation)
    {:ok, %{state | generation: generation}, [directive]}
  end
end

defmodule Jido.Examples.ScheduledOccurrenceProbe.Capture do
  @moduledoc false
  use Jido.Action, name: "example_capture_occurrence"

  def run(input, %{agent_state: state, signal: signal}) do
    with {:ok, occurrence} <- Jido.Plugin.Scheduler.occurrence(signal) do
      tick = %{signal_id: signal.id, data: input, occurrence: occurrence}
      {:ok, %{state | ticks: state.ticks ++ [tick]}}
    end
  end
end

defmodule Jido.Examples.ScheduledOccurrenceProbe do
  @moduledoc """
  REC-03 diagnostic: inspect ticks emitted by the real Scheduler Plugin.

  The Agent stores what the Scheduler sends. It does not create an occurrence
  ID, infer scheduled time from arrival, or add a substitute scheduling loop.
  Keep runs short: captured ticks form an unbounded diagnostic list.
  """
  use Jido.Agent, name: "example_scheduled_occurrences"

  agent do
    schema Zoi.object(%{
             generation: Zoi.integer() |> Zoi.default(0),
             ticks: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/schedule"

    route "recovery.occurrence.arm", __MODULE__.Arm do
      define :arm_schedule, args: [:job_id, :cron]
    end

    route "recovery.occurrence.tick", __MODULE__.Capture
  end
end
