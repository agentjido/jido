defmodule Jido.Examples.AI.SessionAgent.Agent do
  @moduledoc "An AI Agent that owns its canonical Session value in Agent state."

  use Jido.AI.Agent, name: "session_agent_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."
    end
  end
end

defmodule Jido.Examples.AI.SessionAgent do
  @moduledoc "Builds the complete Session-backed AI Agent."

  alias Jido.Examples.AI.SessionAgent.Agent

  @doc "Builds an Agent value. The first request creates its Session."
  def new(opts \\ []), do: Agent.instantiate!(opts)
end
