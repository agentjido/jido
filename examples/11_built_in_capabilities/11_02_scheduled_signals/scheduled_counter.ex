defmodule Jido.Examples.ScheduledCounter do
  @moduledoc """
  An Agent whose Actions can change Timer runtime state with Directives.

  This example uses the current `Jido.Plugin.Timer` because the current
  Agent Server accepts custom Directive handlers only through Plugins. The
  Agent Actions remain in control. They return `Schedule`, `Cron`, and `Cancel`
  Directives. The Timer runtime interprets those values after the Agent
  state commit.
  """

  use Jido.Agent,
    name: "examples_scheduled_counter",
    description: "Changes Timer runtime state with Action Directives",
    plugins: [Jido.Plugin.Timer]

  state do
    schema Jido.Joi.object(%{
             count: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             schedule_requests: Jido.Joi.integer() |> Jido.Joi.min(0) |> Jido.Joi.default(0),
             cron_enabled: Jido.Joi.boolean() |> Jido.Joi.default(false)
           })
  end

  routes do
    signal_source "/examples/runtime/scheduled_counter"

    route "examples.runtime.scheduled_counter.schedule_once", as: :schedule_once do
      action %{delay_ms: delay_ms},
        schema: Jido.Joi.object(%{delay_ms: Jido.Joi.integer() |> Jido.Joi.min(0)}),
        context: context do
        tick =
          Jido.Signal.new!("examples.runtime.scheduled_counter.tick", %{source: :once},
            source: "/examples/runtime/scheduled_counter/timer"
          )

        state = context.agent_state

        {:ok, %{state | schedule_requests: state.schedule_requests + 1}, [Jido.Plugin.Timer.schedule(delay_ms, tick)]}
      end
    end

    route "examples.runtime.scheduled_counter.enable_cron",
      as: :enable_cron,
      defaults: %{expression: "* * * * * * *"} do
      action %{job_id: job_id, expression: expression},
        schema: Jido.Joi.object(%{job_id: Jido.Joi.any(), expression: Jido.Joi.string()}),
        context: context do
        tick =
          Jido.Signal.new!("examples.runtime.scheduled_counter.tick", %{source: job_id},
            source: "/examples/runtime/scheduled_counter/cron"
          )

        directive = Jido.Plugin.Timer.cron(job_id, expression, tick)
        {:ok, %{context.agent_state | cron_enabled: true}, [directive]}
      end
    end

    route "examples.runtime.scheduled_counter.disable_cron", as: :disable_cron do
      action %{job_id: job_id},
        schema: Jido.Joi.object(%{job_id: Jido.Joi.any()}),
        context: context do
        directive = Jido.Plugin.Timer.cancel(job_id)
        {:ok, %{context.agent_state | cron_enabled: false}, [directive]}
      end
    end

    route "examples.runtime.scheduled_counter.tick" do
      action _input,
        schema: Jido.Joi.object(%{source: Jido.Joi.any()}),
        context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end
