defmodule Jido.Examples.Conversation.RestorableAgent do
  @moduledoc "An AI Agent whose Session is part of its portable Agent snapshot."

  use Jido.AI.Agent, name: "conversation_restorable_agent"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "offline:restore"
      instructions "Return the deterministic offline answer."
    end
  end
end

defmodule Jido.Examples.Conversation.Restoration do
  @moduledoc "Captures and restores one complete portable Agent value."

  @doc "Captures a portable snapshot without writing a storage adapter."
  def snapshot(agent), do: Jido.Persistence.snapshot(agent)

  @doc "Restores the saved definition and state from a snapshot."
  def restore(snapshot), do: Jido.Persistence.restore(snapshot)
end
