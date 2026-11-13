defmodule Jido.Examples.AI.ToolFlow.Multiply do
  @moduledoc "Multiplies two integers."

  use Jido.Action,
    name: "multiply",
    description: "Multiply two integers",
    schema: Jido.Joi.object(%{left: Jido.Joi.integer(), right: Jido.Joi.integer()})

  @impl Jido.Action
  def run(%{left: left, right: right}, context) do
    if counter = Map.get(context, :counter), do: Agent.update(counter, &(&1 + 1))
    {:ok, %{product: left * right}}
  end
end

defmodule Jido.Examples.AI.ToolFlow.MultiplyFlow do
  @moduledoc "Runs the multiply Action through a Flow."

  use Jido.Flow,
    name: "multiply_flow",
    description: "Multiply two integers through a Flow",
    schema: Jido.Joi.object(%{left: Jido.Joi.integer(), right: Jido.Joi.integer()})

  flow do
    step "multiply", action: Jido.Examples.AI.ToolFlow.Multiply, params: input()
    output result("multiply")
  end
end

defmodule Jido.Examples.AI.ToolFlow.Agent do
  @moduledoc "A response that can run a Jido Action or Flow as a tool."

  use Jido.AI.Agent, name: "tool_flow_example"

  ai do
    reasoning Jido.AI.Reasoning.ReAct do
      model "openai:gpt-4o-mini"
      instructions "Use a calculation tool when it is useful."

      limits do
        elapsed_ms(5_000)
        tool_rounds 2
        model_calls 3
        tool_calls 4
      end
    end

    tools do
      action Jido.Examples.AI.ToolFlow.Multiply
      flow Jido.Examples.AI.ToolFlow.MultiplyFlow
    end
  end
end
