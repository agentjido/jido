defmodule Jido.Examples.ConversationHistory.Reply do
  @moduledoc false
  alias Jido.Examples.LLM.Adapter

  use Jido.Action,
    name: "llm_history_reply",
    schema:
      Zoi.object(%{message_id: Zoi.string() |> Zoi.min(1), text: Zoi.string() |> Zoi.min(1)})

  def run(input, %{agent_state: state} = context) do
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
end

defmodule Jido.Examples.ConversationHistory do
  @moduledoc "Agent-owned history, explicit duplicate rejection, and portable persistence."

  use Jido.Agent, name: "llm_history_agent"

  agent do
    schema Zoi.object(%{
             messages: Zoi.list(Zoi.map()) |> Zoi.default([]),
             processed_ids: Zoi.list(Zoi.string()) |> Zoi.default([])
           })
  end

  routes do
    signal_source "/examples/llm"

    route "llm.history", Jido.Examples.ConversationHistory.Reply do
      define :append_message, args: [:message_id, :text]
    end
  end
end
