defmodule Jido.Examples.Plugins.Identity.Agent do
  @moduledoc "Verifies signed input before routing and signs replies after execution."

  alias Jido.Joi

  alias Jido.Examples.Plugins.Crypto
  alias Jido.Examples.Plugins.Identity.Plugin

  use Jido.Agent,
    name: "application_identity_agent",
    plugins: [
      {Plugin, %{trusted_public_key: elem(Crypto.peer_key_pair(), 0)}}
    ]

  state do
    schema Joi.object(%{
             accepted: Joi.integer() |> Joi.default(0),
             last_public_key: Joi.string() |> Joi.default("")
           })
  end

  routes do
    signal_source "/examples/plugins/identity"

    route "examples.plugins.identity.challenge" do
      action %{"challenge" => challenge},
        schema: Joi.object(%{"challenge" => Joi.string() |> Joi.min(1)}),
        output_schema:
          Joi.object(%{
            state: Joi.map(),
            reply: Joi.object(%{"challenge" => Joi.string()})
          }),
        context: context do
        next_state = %{
          context.agent_state
          | accepted: context.agent_state.accepted + 1,
            last_public_key:
              context.plugin_inputs[Plugin]
              |> Map.fetch!(:prepared)
              |> Map.fetch!(:public_key)
              |> Base.encode16(case: :lower)
        }

        {:ok, %{state: next_state, reply: %{"challenge" => challenge}}}
      end

      state(from: output(:state))
      reply("examples.plugins.identity.accepted", from: output(:reply))
    end
  end
end
