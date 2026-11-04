defmodule Jido.Examples.Applications.Subscription.Agent do
  @moduledoc "Stores desired subscriptions in Plugin state and rebuilds runtime state after restart."
  use Jido.Agent,
    name: "application_subscription_agent",
    plugins: [Jido.Examples.Applications.Subscription.Plugin]

  state do
    schema Jido.Joi.object(%{
             changes: Jido.Joi.integer() |> Jido.Joi.default(0),
             events: Jido.Joi.list(Jido.Joi.map()) |> Jido.Joi.default([])
           })
  end

  routes do
    signal_source "/examples/applications/subscription"

    route "examples.applications.subscription.change", as: :change do
      action input,
        schema:
          Jido.Joi.object(%{
            operation: Jido.Joi.enum([:subscribe, :unsubscribe]),
            topic: Jido.Joi.string() |> Jido.Joi.min(1),
            config: Jido.Joi.map() |> Jido.Joi.default(%{})
          }),
        context: context do
        plugin = Jido.Examples.Applications.Subscription.Plugin
        next_state = %{context.agent_state | changes: context.agent_state.changes + 1}

        directive =
          case input.operation do
            :subscribe -> plugin.subscribe(input.topic, input.config)
            :unsubscribe -> plugin.unsubscribe(input.topic)
          end

        {:ok, next_state, [directive]}
      end
    end

    route "examples.applications.subscription.input" do
      action %{topic: topic, text: text},
        schema: Jido.Joi.object(%{topic: Jido.Joi.string(), text: Jido.Joi.string()}),
        context: context do
        if Map.has_key?(context.agent_state.subscriptions.desired, topic) do
          event = %{topic: topic, text: text}
          {:ok, %{context.agent_state | events: context.agent_state.events ++ [event]}}
        else
          {:error, Jido.Error.validation_error("stale subscription resource")}
        end
      end
    end
  end
end
