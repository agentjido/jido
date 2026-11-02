defmodule Jido.AI.Reasoning.TreeOfThoughts.Actions.ExpandNext do
  @moduledoc "Continues the bounded Tree of Thoughts loop or returns its result."

  alias Jido.AI.Reasoning.TreeOfThoughts.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/tree-of-thoughts/actions/expand-next",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_expand_next",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}
  def run(%{kind: :model, input: input}, _context), do: {:continue, input, ModelRound}
end
