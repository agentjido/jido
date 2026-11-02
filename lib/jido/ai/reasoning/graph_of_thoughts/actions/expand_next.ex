defmodule Jido.AI.Reasoning.GraphOfThoughts.Actions.ExpandNext do
  @moduledoc "Continues Graph of Thoughts synthesis or returns its result."

  alias Jido.AI.Reasoning.GraphOfThoughts.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/graph-of-thoughts/actions/expand-next",
    vsn: 1,
    name: "jido_ai_graph_of_thoughts_expand_next",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}
  def run(%{kind: :model, input: input}, _context), do: {:continue, input, ModelRound}
end
