defmodule Jido.Examples.AI.BasicAgent.Agent do
  @moduledoc "A core Jido Agent with one static AI configuration."

  use Jido.AI.Agent, name: "basic_ai_agent_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Reply in one short sentence."
    end
  end
end
