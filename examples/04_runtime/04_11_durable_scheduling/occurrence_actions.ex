defmodule Jido.Examples.ScheduledOccurrenceRecovery.Arm do
  @moduledoc "Creates a new durable schedule generation."

  use Jido.Action,
    name: "example_arm_durable_occurrences",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), cron: Zoi.string()})

  @impl true
  def run(input, %{agent_state: state}) do
    generation = state.generation + 1

    tick =
      Jido.Signal.new!(
        "examples.runtime.schedule.tick",
        %{job_id: input.job_id, generation: generation},
        source: "/examples/runtime/durable_schedule"
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
  @moduledoc "Admits one current occurrence and acknowledges it with the result."

  use Jido.Action, name: "example_capture_durable_occurrence"

  alias Jido.Plugin.Scheduler

  @impl true
  def run(input, %{agent_state: state, signal: signal}) do
    with :ok <- Scheduler.admit_occurrence(state.scheduler, signal),
         {:ok, occurrence} <- Scheduler.occurrence(signal) do
      tick = %{signal_id: signal.id, data: input, occurrence: occurrence}
      {:ok, %{state | ticks: state.ticks ++ [tick]}, [Scheduler.acknowledge(occurrence.id)]}
    end
  end
end

defmodule Jido.Examples.ScheduledOccurrenceRecovery.Cancel do
  @moduledoc "Cancels one durable schedule."

  use Jido.Action,
    name: "example_cancel_occurrences",
    schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1)})

  @impl true
  def run(input, %{agent_state: state}),
    do: {:ok, state, [Jido.Plugin.Scheduler.cancel(input.job_id)]}
end
