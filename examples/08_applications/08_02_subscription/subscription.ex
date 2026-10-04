defmodule Jido.Examples.Applications.Subscription.Agent do
  @moduledoc "Stores desired subscriptions in Plugin state and rebuilds runtime state after restart."
  use Jido.Agent, name: "application_subscription_agent"

  agent do
    schema Zoi.object(%{
             changes: Zoi.integer() |> Zoi.default(0),
             events: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    plugin Jido.Examples.Applications.Subscription.Plugin
  end

  routes do
    signal_source "/examples/applications/subscription"

    route "examples.applications.subscription.change", as: :change do
      action input,
        schema:
          Zoi.object(%{
            operation: Zoi.enum([:subscribe, :unsubscribe]),
            topic: Zoi.string() |> Zoi.min(1),
            config: Zoi.map() |> Zoi.default(%{})
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
        schema: Zoi.object(%{topic: Zoi.string(), text: Zoi.string()}),
        context: context do
        if Map.has_key?(context.agent_state.subscriptions.desired, topic) do
          event = %{topic: topic, text: text}
          {:ok, %{context.agent_state | events: context.agent_state.events ++ [event]}}
        else
          {:error, Jido.Action.Error.validation_error("stale subscription resource")}
        end
      end
    end
  end
end
