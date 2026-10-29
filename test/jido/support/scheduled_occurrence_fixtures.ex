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

defmodule JidoTest.ScheduledOccurrenceFixtures.FastRuntimeAgent do
  @moduledoc false

  alias Jido.Plugin.Scheduler
  alias JidoTest.AgentRuntimeFixtures.{Record, ReturnDirective, Tick}
  alias JidoTest.ScheduledOccurrenceFixtures.Clock

  use Jido.Agent, name: "fast_runtime_agent", plugins: [{Scheduler, %{time_scale: Clock}}]

  state do
    schema Zoi.object(%{
             events: Zoi.list(Zoi.any()) |> Zoi.default([]),
             ticks: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    route "runtime.directive", ReturnDirective
    route "runtime.record", Record
    route "cron.tick", Tick
  end
end

defmodule JidoTest.ScheduledOccurrenceFixtures.TimedAgent do
  @moduledoc false

  alias Jido.Plugin.Scheduler
  alias Jido.Signal
  alias JidoTest.ScheduledOccurrenceFixtures.Clock

  use Jido.Agent, name: "timed_occurrence_probe", plugins: [{Scheduler, %{time_scale: Clock}}]

  state do
    schema Zoi.object(%{
             generation: Zoi.integer() |> Zoi.default(0),
             ticks: Zoi.list(Zoi.map()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/test/scheduled_occurrences"

    route "test.schedule.arm", as: :arm_schedule do
      action input,
        schema: Zoi.object(%{job_id: Zoi.string() |> Zoi.min(1), cron: Zoi.string()}),
        context: context do
        generation = context.agent_state.generation + 1

        tick =
          Signal.new!(
            "test.schedule.tick",
            %{job_id: input.job_id, generation: generation},
            source: "/test/scheduled_occurrences"
          )

        directive =
          Scheduler.cron(input.job_id, input.cron, tick, generation: generation)

        {:ok, %{context.agent_state | generation: generation}, [directive]}
      end
    end

    route "test.schedule.tick" do
      action input, context: context do
        with {:ok, occurrence} <- Scheduler.occurrence(context.signal) do
          tick = %{signal_id: context.signal.id, data: input, occurrence: occurrence}
          {:ok, %{context.agent_state | ticks: context.agent_state.ticks ++ [tick]}}
        end
      end
    end
  end
end
