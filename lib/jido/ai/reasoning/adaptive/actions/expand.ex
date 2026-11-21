defmodule Jido.AI.Reasoning.Adaptive.Actions.Expand do
  alias Jido.Joi
  @moduledoc "Expands an Adaptive selection into the selected reasoning Flow."

  alias Jido.AI.Reasoning.{
    AlgorithmOfThoughts,
    ChainOfDraft,
    ChainOfThought,
    GraphOfThoughts,
    ReAct,
    TreeOfThoughts,
    TRM
  }

  @strategies %{
    react: ReAct,
    chain_of_thought: ChainOfThought,
    chain_of_draft: ChainOfDraft,
    algorithm_of_thoughts: AlgorithmOfThoughts,
    tree_of_thoughts: TreeOfThoughts,
    graph_of_thoughts: GraphOfThoughts,
    trm: TRM
  }

  use Jido.Action,
    id: "jido.ai/reasoning/adaptive/actions/expand",
    vsn: 1,
    name: "jido_ai_adaptive_expand",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{strategy: strategy, input: input}, _context) do
    case Map.fetch(@strategies, strategy) do
      {:ok, flow} -> {:continue, input, flow}
      :error -> {:error, {:unknown_reasoning_strategy, strategy}}
    end
  end
end
