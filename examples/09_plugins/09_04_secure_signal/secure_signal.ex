defmodule Jido.Examples.Plugins.SecureSignal.Agent do
  @moduledoc "Verifies and decrypts secure input, then encrypts and signs its correlated reply."
  use Jido.Agent, name: "application_secure_signal_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             peer: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Plugins.Identity.Plugin,
      config: [
        trusted_public_key: elem(Jido.Examples.Plugins.Crypto.peer_key_pair(), 0)
      ]

    plugin Jido.Examples.Plugins.SecureSignal.Plugin
  end

  routes do
    signal_source "/examples/plugins/secure_signal"

    route "examples.plugins.secure_signal.request" do
      action %{"message_id" => message_id},
        schema: Zoi.object(%{"message_id" => Zoi.string() |> Zoi.min(1)}),
        context: context do
        secure = context.plugin_inputs[Jido.Examples.Plugins.SecureSignal.Plugin]

        reply =
          Jido.Signal.new!(
            "examples.plugins.secure_signal.accepted",
            %{
              "message_id" => message_id,
              "secure" => %{"receipt" => secure["secret"] <> ":accepted"}
            },
            source: "/examples/plugins/secure_signal/agent"
          )

        next_state = %{
          context.agent_state
          | accepted: context.agent_state.accepted + 1,
            peer:
              context.plugin_inputs[Jido.Examples.Plugins.Identity.Plugin]
              |> Map.fetch!(:public_key)
              |> Base.encode16(case: :lower)
        }

        {:ok, next_state, [Jido.Agent.Directive.emit(reply)]}
      end
    end
  end
end
