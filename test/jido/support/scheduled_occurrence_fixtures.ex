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

    plugin Jido.Plugin.Scheduler,
      config: [time_scale: JidoTest.ScheduledOccurrenceFixtures.Clock, delivery_interval: 25]
  end

  routes do
    route "jido.scheduler.enqueue", Jido.Plugin.Scheduler.Enqueue
    route "examples.runtime.schedule.arm", ScheduledOccurrenceRecovery.Arm
    route "examples.runtime.schedule.tick", ScheduledOccurrenceRecovery.Capture
    route "examples.runtime.schedule.cancel", ScheduledOccurrenceRecovery.Cancel
  end
end

defmodule JidoTest.ScheduledOccurrenceFixtures.FastRuntimeAgent do
  @moduledoc false

  alias JidoTest.AgentRuntimeFixtures.{Record, ReturnDirective, Tick}

  use Jido.Agent,
    name: "fast_runtime_agent",
    schema:
      Zoi.object(%{
        events: Zoi.list(Zoi.any()) |> Zoi.default([]),
        ticks: Zoi.integer() |> Zoi.default(0)
      }),
    routes: [
      {"runtime.directive", ReturnDirective},
      {"runtime.record", Record},
      {"cron.tick", Tick}
    ],
    plugins: [
      {Jido.Plugin.Scheduler, time_scale: JidoTest.ScheduledOccurrenceFixtures.Clock}
    ]
end

defmodule JidoTest.ScheduledOccurrenceFixtures.TimedAgent do
  @moduledoc false
  use Jido.Agent, name: "timed_occurrence_probe"

  agent do
    schema Zoi.object(%{
             generation: Zoi.integer() |> Zoi.default(0),
             ticks: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Plugin.Scheduler, config: [time_scale: JidoTest.ScheduledOccurrenceFixtures.Clock]
  end

  routes do
    signal_source "/test/scheduled_occurrences"

    route "test.schedule.arm" do
      action input,
        schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), cron: Zoi.string()}),
        context: context do
        generation = context.agent_state.generation + 1

        tick =
          Jido.Signal.new!(
            "test.schedule.tick",
            %{job_id: input.job_id, generation: generation},
            source: "/test/scheduled_occurrences"
          )

        directive =
          Jido.Plugin.Scheduler.cron(input.job_id, input.cron, tick, generation: generation)

        {:ok, %{context.agent_state | generation: generation}, [directive]}
      end

      define :arm_schedule, args: [:job_id, :cron]
    end

    route "test.schedule.tick" do
      action input, context: context do
        with {:ok, occurrence} <- Jido.Plugin.Scheduler.occurrence(context.signal) do
          tick = %{signal_id: context.signal.id, data: input, occurrence: occurrence}
          {:ok, %{context.agent_state | ticks: context.agent_state.ticks ++ [tick]}}
        end
      end
    end
  end
end
