defmodule Jido.Examples.AI.ThreadAgent.Agent do
  @moduledoc "A graph-first AI Agent that commits model messages to one portable Session Thread."

  use Jido.AI.Agent, name: "thread_agent_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Answer in one short sentence."
    end
  end
end
