defmodule Jido.Examples.AI.ConversationHistory.Agent do
  @moduledoc "An AI Agent that projects bounded complete exchanges from its committed Session."

  use Jido.AI.Agent, name: "conversation_history_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Use the committed conversation and answer briefly."

      context do
        max_messages 4
        max_bytes 20_000
      end
    end
  end
end

defmodule Jido.Examples.AI.ConversationHistory do
  @moduledoc "Builds the AI Agent used to teach committed conversation projection."

  alias Jido.Examples.AI.ConversationHistory.Agent

  @doc "Builds an Agent whose later requests use its committed Session."
  def new(opts \\ []), do: Agent.instantiate!(opts)
end
