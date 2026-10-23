defmodule Jido.Examples.Plugins.SecureSignal.Agent do
  @moduledoc "Verifies and decrypts secure input, then encrypts and signs its correlated reply."
  use Jido.Agent, name: "application_secure_signal_agent"

  state do
    schema Zoi.object(%{
             accepted: Zoi.integer() |> Zoi.default(0),
             peer: Zoi.string() |> Zoi.default("")
           })
  end

  plugins do
    plugin Jido.Examples.Plugins.SecureSignal.Identity.Plugin,
      config: %{
        trusted_public_key: elem(Jido.Examples.Plugins.Crypto.peer_key_pair(), 0)
      }

    plugin Jido.Examples.Plugins.SecureSignal.Plugin
  end

  routes do
    signal_source "/examples/plugins/secure_signal"

    route "examples.plugins.secure_signal.request" do
      action %{"message_id" => message_id},
        schema: Zoi.object(%{"message_id" => Zoi.string() |> Zoi.min(1)}),
        output_schema:
          Zoi.object(%{
            state: Zoi.map(),
            reply:
              Zoi.object(%{
                "message_id" => Zoi.string(),
                "secure" => Zoi.map()
              })
          }),
        context: context do
        secure = context.plugin_inputs[Jido.Examples.Plugins.SecureSignal.Plugin].runtime

        next_state = %{
          context.agent_state
          | accepted: context.agent_state.accepted + 1,
            peer:
              context.plugin_inputs[Jido.Examples.Plugins.SecureSignal.Identity.Plugin]
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
