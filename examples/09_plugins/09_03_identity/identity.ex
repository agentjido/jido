defmodule Jido.Examples.Plugins.Identity.Agent do
  @moduledoc "Verifies signed input before routing and signs emitted replies after execution."
  use Jido.Agent, name: "application_identity_agent"

  agent do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             last_public_key: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Examples.Plugins.Identity.Plugin,
      config: [
        trusted_public_key: elem(Jido.Examples.Plugins.Crypto.peer_key_pair(), 0)
      ]
  end

  routes do
    signal_source "/examples/plugins/identity"

    route "examples.plugins.identity.challenge" do
      action %{"challenge" => challenge},
        schema: Zoi.object(%{"challenge" => Zoi.string() |> Zoi.min(1)}),
        context: context do
        reply =
          Jido.Signal.new!(
            "examples.plugins.identity.accepted",
            %{"challenge" => challenge},
            source: "/examples/plugins/identity/agent"
          )

        next_state = %{
          context.agent_state
          | accepted: context.agent_state.accepted + 1,
            last_public_key:
              context.plugin_inputs[Jido.Examples.Plugins.Identity.Plugin]
              |> Map.fetch!(:prepared)
              |> Map.fetch!(:public_key)
              |> Base.encode16(case: :lower)
        }

        {:ok, next_state, [Jido.Agent.Directive.emit(reply)]}
      end
    end
  end
end
