defmodule Jido.Examples.ScheduledOccurrenceRecovery.Arm do
  @moduledoc false
  use Jido.Action,
    name: "example_arm_durable_occurrences",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), cron: Zoi.string()})

  def run(input, %{agent_state: state}) do
    generation = state.generation + 1

    tick =
      Jido.Signal.new!(
        "recovery.occurrence.tick",
        %{job_id: input.job_id, generation: generation},
        source: "/examples/schedule"
      )

    cron =
      Jido.Plugin.Scheduler.cron(input.job_id, input.cron, tick,
        generation: generation,
        delivery: :durable
      )

    {:ok, %{state | generation: generation}, [cron]}
  end
end

defmodule Jido.Examples.ScheduledOccurrenceRecovery.Capture do
  @moduledoc false
  use Jido.Action, name: "example_capture_durable_occurrence"
  alias Jido.Plugin.Scheduler

  def run(input, %{agent_state: state, signal: signal}) do
    with {:ok, occurrence} <- Scheduler.occurrence(signal) do
      tick = %{signal_id: signal.id, data: input, occurrence: occurrence}
      {:ok, %{state | ticks: state.ticks ++ [tick]}, [Scheduler.acknowledge(occurrence.id)]}
    end
  end
end

defmodule Jido.Examples.ScheduledOccurrenceRecovery.Cancel do
  @moduledoc false
  use Jido.Action,
    name: "example_cancel_occurrences",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1)})

  def run(input, %{agent_state: state}),
    do: {:ok, state, [Jido.Plugin.Scheduler.cancel(input.job_id)]}
end

defmodule Jido.Examples.ScheduledOccurrenceRecovery do
  @moduledoc """
  REC-03: save a due occurrence before work and acknowledge it with the result.

  Start this Agent with persistence and restore enabled for crash recovery.
  Scheduler keeps one pending occurrence per job and skips further slots while
  it is pending. It retries saved work after loss and skips other offline slots.
  The recorded tick list is an unbounded diagnostic; keep example runs short.
  """
  use Jido.Agent, name: "example_durable_schedule"

  agent do
    schema Jido.Examples.ScheduledOccurrenceProbe.domain_schema()
    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/schedule"

    route "recovery.occurrence.arm", __MODULE__.Arm do
      define :arm_schedule, args: [:job_id, :cron]
    end

    route "recovery.occurrence.cancel", __MODULE__.Cancel do
      define :cancel_schedule, args: [:job_id]
    end

    route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue
    route "recovery.occurrence.tick", __MODULE__.Capture
  end
end
