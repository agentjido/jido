defmodule Jido.Examples.Plugins.SecureSignal.Agent do
  @moduledoc "Verifies and decrypts secure input, then encrypts and signs its correlated reply."
  alias Jido.Examples.Plugins.Crypto
  alias Jido.Examples.Plugins.SecureSignal.Identity.Plugin, as: IdentityPlugin
  alias Jido.Examples.Plugins.SecureSignal.Plugin, as: SecureSignalPlugin

  use Jido.Agent,
    name: "application_secure_signal_agent",
    plugins: [
      {IdentityPlugin, %{trusted_public_key: elem(Crypto.peer_key_pair(), 0)}},
      SecureSignalPlugin
    ]

  state do
    schema Jido.Joi.object(%{
             accepted: Jido.Joi.integer() |> Jido.Joi.default(0),
             peer: Jido.Joi.string() |> Jido.Joi.default("")
           })
  end

  routes do
    signal_source "/examples/plugins/secure_signal"

    route "examples.plugins.secure_signal.request" do
      action %{"message_id" => message_id},
        schema: Jido.Joi.object(%{"message_id" => Jido.Joi.string() |> Jido.Joi.min(1)}),
        output_schema:
          Jido.Joi.object(%{
            state: Jido.Joi.map(),
            reply:
              Jido.Joi.object(%{
                "message_id" => Jido.Joi.string(),
                "secure" => Jido.Joi.map()
              })
          }),
        context: context do
        secure = context.plugin_inputs[SecureSignalPlugin].runtime

        next_state = %{
          context.agent_state
          | accepted: context.agent_state.accepted + 1,
            peer:
              context.plugin_inputs[IdentityPlugin]
              |> Map.fetch!(:prepared)
              |> Map.fetch!(:public_key)
              |> Base.encode16(case: :lower)
        }

        {:ok,
         %{
           state: next_state,
           reply: %{
             "message_id" => message_id,
             "secure" => %{"receipt" => secure["secret"] <> ":accepted"}
           }
         }}
      end

      state(from: output(:state))
      reply("examples.plugins.secure_signal.accepted", from: output(:reply))
    end
  end
end
