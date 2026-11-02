defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.Actions.ExpandNext do
  alias Jido.Joi
  @moduledoc "Expands the trusted Algorithm of Thoughts routing decision."

  alias Jido.AI.Reasoning.AlgorithmOfThoughts.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/algorithm-of-thoughts/actions/expand-next",
    vsn: 1,
    name: "jido_ai_algorithm_of_thoughts_expand_next",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}
  def run(%{kind: :model, input: input}, _context), do: {:continue, input, ModelRound}
end
