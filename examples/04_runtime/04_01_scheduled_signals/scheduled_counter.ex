defmodule Jido.Examples.ScheduledCounter do
  @moduledoc """
  An Agent whose Actions can change Scheduler runtime state with Directives.

  This example uses the current `Jido.Plugin.Scheduler` because the current
  Agent Server accepts custom Directive handlers only through Plugins. The
  Agent Actions remain in control. They return `Schedule`, `Cron`, and `Cancel`
  Directives. The Scheduler runtime interprets those values after the Agent
  state commit.
  """

  use Jido.Agent,
    name: "examples_scheduled_counter",
    description: "Changes Scheduler runtime state with Action Directives"

  agent do
    schema Zoi.object(%{
             count: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             schedule_requests: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
             cron_enabled: Zoi.boolean() |> Zoi.default(false)
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/scheduled_counter"

    route "examples.scheduled.schedule_once", Jido.Examples.ScheduledCounter.ScheduleOnce do
      define :schedule_once, args: [:delay_ms]
    end

    route "examples.scheduled.enable_cron", Jido.Examples.ScheduledCounter.EnableCron do
      defaults %{expression: "* * * * * * *"}
      define :enable_cron, args: [:job_id, {:optional, :expression}]
    end

    route "examples.scheduled.disable_cron" do
      action %{job_id: job_id},
        name: "examples_scheduled_counter_disable_cron",
        schema: Zoi.object(%{job_id: Zoi.any()}),
        context: context do
        directive = Jido.Plugin.Scheduler.cancel(job_id)
        {:ok, %{context.agent_state | cron_enabled: false}, [directive]}
      end

      define :disable_cron, args: [:job_id]
    end

    route "examples.scheduled.tick" do
      action _input, name: "examples_scheduled_counter_tick", context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end

defmodule Jido.Examples.ScheduledCounter.ScheduleOnce do
  @moduledoc false

  use Jido.Action,
    name: "examples_scheduled_counter_schedule_once",
    schema: Zoi.object(%{delay_ms: Zoi.integer() |> Zoi.min(0)})

  alias Jido.Plugin.Scheduler
  alias Jido.Signal

  @impl Jido.Action
  def run(%{delay_ms: delay_ms}, %{agent_state: state}) do
    tick =
      Signal.new!("examples.scheduled.tick", %{source: :once},
        source: "/examples/scheduled_counter/timer"
      )

    {:ok, %{state | schedule_requests: state.schedule_requests + 1},
     [Scheduler.schedule(delay_ms, tick)]}
  end
end

defmodule Jido.Examples.ScheduledCounter.EnableCron do
  @moduledoc false

  use Jido.Action,
    name: "examples_scheduled_counter_enable_cron",
    schema: Zoi.object(%{job_id: Zoi.any(), expression: Zoi.string()})

  alias Jido.Plugin.Scheduler
  alias Jido.Signal

  @impl Jido.Action
  def run(%{job_id: job_id, expression: expression}, %{agent_state: state}) do
    tick =
      Signal.new!("examples.scheduled.tick", %{source: job_id},
        source: "/examples/scheduled_counter/cron"
      )

    {:ok, %{state | cron_enabled: true}, [Scheduler.cron(job_id, expression, tick)]}
  end
end
