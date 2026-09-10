defmodule Jido.Examples.Factory.LiveConversation do
  @moduledoc "One live LLM request per chat turn. State contains text history, never provider keys."
  use Jido.Agent, name: "factory_live_conversation"

  agent do
    schema Zoi.object(%{
             messages:
               Zoi.list(Zoi.map())
               |> Zoi.default([
                 %{
                   role: :system,
                   content: "You are a helpful assistant. Use clear, short answers."
                 }
               ]),
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             answer: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/examples/factory/chat"

    route "examples.factory.live_conversation.chat" do
      action input,
        schema:
          Zoi.object(%{
            request_id: Zoi.string() |> Zoi.min(1),
            text: Zoi.string() |> Zoi.min(1) |> Zoi.max(20_000)
          }),
        context: context do
        state = context.agent_state

        if input.request_id in state.seen do
          {:error, Jido.Action.Error.validation_error("Request ID is already used")}
        else
          messages = state.messages ++ [%{role: :user, content: input.text}]
          context = Map.put(context, :stream_id, input.request_id)

          with {:ok, %{text: text}} <- Jido.Examples.Factory.Model.reply(messages, context) do
            {:ok,
             %{
               state
               | messages: messages ++ [%{role: :assistant, content: text}],
                 seen: state.seen ++ [input.request_id],
                 answer: text
             }}
          end
        end
      end

      define :chat, args: [:request_id, :text]
    end
  end
end
