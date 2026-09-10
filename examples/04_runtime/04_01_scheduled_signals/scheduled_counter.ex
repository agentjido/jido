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
    signal_source "/examples/runtime/scheduled_counter"

    route "examples.runtime.scheduled_counter.schedule_once" do
      action %{delay_ms: delay_ms},
        schema: Zoi.object(%{delay_ms: Zoi.integer() |> Zoi.min(0)}),
        context: context do
        tick =
          Jido.Signal.new!("examples.runtime.scheduled_counter.tick", %{source: :once},
            source: "/examples/runtime/scheduled_counter/timer"
          )

        state = context.agent_state

        {:ok, %{state | schedule_requests: state.schedule_requests + 1},
         [Jido.Plugin.Scheduler.schedule(delay_ms, tick)]}
      end

      define :schedule_once, args: [:delay_ms]
    end

    route "examples.runtime.scheduled_counter.enable_cron" do
      defaults %{expression: "* * * * * * *"}

      action %{job_id: job_id, expression: expression},
        schema: Zoi.object(%{job_id: Zoi.any(), expression: Zoi.string()}),
        context: context do
        tick =
          Jido.Signal.new!("examples.runtime.scheduled_counter.tick", %{source: job_id},
            source: "/examples/runtime/scheduled_counter/cron"
          )

        directive = Jido.Plugin.Scheduler.cron(job_id, expression, tick)
        {:ok, %{context.agent_state | cron_enabled: true}, [directive]}
      end

      define :enable_cron, args: [:job_id, {:optional, :expression}]
    end

    route "examples.runtime.scheduled_counter.disable_cron" do
      action %{job_id: job_id},
        schema: Zoi.object(%{job_id: Zoi.any()}),
        context: context do
        directive = Jido.Plugin.Scheduler.cancel(job_id)
        {:ok, %{context.agent_state | cron_enabled: false}, [directive]}
      end

      define :disable_cron, args: [:job_id]
    end

    route "examples.runtime.scheduled_counter.tick" do
      action _input, context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end
