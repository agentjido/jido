defmodule JidoTest.ScheduledOccurrenceFixtures.Clock do
  @moduledoc false
  @behaviour SchedEx.TimeScale

  def start_link(_opts),
    do: Elixir.Agent.start_link(fn -> ~U[2030-01-01 00:00:00.100000Z] end, name: __MODULE__)

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
  def set(time), do: Elixir.Agent.update(__MODULE__, fn _ -> time end)
  @impl true
  def now("Etc/UTC"), do: Elixir.Agent.get(__MODULE__, & &1)
  @impl true
  def speedup, do: 20
end

defmodule JidoTest.ScheduledOccurrenceFixtures.DurableAgent do
  @moduledoc false
  alias Jido.Examples.ScheduledOccurrenceRecovery
  use Jido.Agent, name: "durable_occurrence_probe"

  agent do
    schema ScheduledOccurrenceRecovery.domain_schema()
    plugin Jido.Plugin.Scheduler, config: [time_scale: JidoTest.ScheduledOccurrenceFixtures.Clock]
  end

  routes do
    route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue
    route "recovery.occurrence.arm", ScheduledOccurrenceRecovery.Arm
    route "recovery.occurrence.tick", ScheduledOccurrenceRecovery.Capture
    route "recovery.occurrence.cancel", ScheduledOccurrenceRecovery.Cancel
  end
end

defmodule JidoTest.ScheduledOccurrenceFixtures.TimedAgent do
  @moduledoc false
  alias Jido.Examples.ScheduledOccurrenceProbe
  use Jido.Agent, name: "timed_occurrence_probe"

  agent do
    schema ScheduledOccurrenceProbe.domain_schema()
    plugin Jido.Plugin.Scheduler, config: [time_scale: JidoTest.ScheduledOccurrenceFixtures.Clock]
  end

  routes do
    route "recovery.occurrence.arm", ScheduledOccurrenceProbe.Arm
    route "recovery.occurrence.tick", ScheduledOccurrenceProbe.Capture
  end
end
