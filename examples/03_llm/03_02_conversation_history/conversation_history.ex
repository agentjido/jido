defmodule Jido.Examples.ConversationHistory do
  @moduledoc "Agent-owned history with duplicate rejection and portable state."

  use Jido.Agent, name: "examples_llm_conversation_history"

  agent do
    schema Zoi.object(%{
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             processed_ids: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm/conversation_history"

    route "examples.llm.conversation_history.append" do
      action input,
        schema:
          Zoi.object(%{
            message_id: Zoi.string() |> Zoi.min(1),
            text: Zoi.string() |> Zoi.min(1)
          }),
        context: context do
        alias Jido.Examples.LLM.Adapter

        state = context.agent_state

        if input.message_id in state.processed_ids do
          Adapter.invalid("duplicate message ID")
        else
          messages = state.messages ++ [%{role: :user, content: input.text}]

          with {:ok, raw} <- Adapter.call(context, :model, :complete, %{messages: messages}),
               {:ok, result} <- Adapter.parse(Adapter.answer_schema(), raw) do
            {:ok,
             %{
               messages: messages ++ [%{role: :assistant, content: result.answer}],
               processed_ids: state.processed_ids ++ [input.message_id]
             }}
          end
        end
      end

      define :append_message, args: [:message_id, :text]
    end
  end
end
