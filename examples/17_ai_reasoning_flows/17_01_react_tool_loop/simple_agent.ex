unless Code.ensure_loaded?(Jido.Examples.AI.Tools.Add) do
  Code.require_file("../../15_ai_agents/support/arithmetic_tools.ex", __DIR__)
end

defmodule Jido.Examples.AI.SimpleAgent do
  @moduledoc "A minimal graph-first AI Agent example."

  use Jido.AI.Agent,
    name: "jido_ai_simple_agent",
    description: "Answer one request with guardrails and multiple tools",
    id: "jido.ai/agents/simple",
    vsn: 3

  ai do
    reasoning Jido.AI.Reasoning.ReAct

    tools do
      action Jido.Examples.AI.Tools.Add
      action Jido.Examples.AI.Tools.Multiply
    end
  end
end
