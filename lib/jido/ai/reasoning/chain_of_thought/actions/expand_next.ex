defmodule Jido.AI.Reasoning.ChainOfThought.Actions.ExpandNext do
  alias Jido.Joi
  @moduledoc "Expands the trusted Chain of Thought model decision."

  alias Jido.AI.Reasoning.ChainOfThought.ModelRound

  use Jido.Action,
    id: "jido.ai/reasoning/chain-of-thought/actions/expand-next",
    vsn: 1,
    name: "jido_ai_chain_of_thought_expand_next",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}

  def run(%{kind: :model, input: input}, _context),
    do: {:continue, input, ModelRound}
end
