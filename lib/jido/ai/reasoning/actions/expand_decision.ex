defmodule Jido.AI.Reasoning.Actions.ExpandDecision do
  alias Jido.Joi

  @moduledoc "Expands a trusted reasoning decision with an explicit next target."

  use Jido.Action,
    id: "jido.ai/reasoning/actions/expand-decision",
    vsn: 1,
    name: "jido_ai_expand_reasoning_decision",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}

  def run(%{kind: :model, input: input, target: target}, _context)
      when is_atom(target) and target not in [nil, true, false],
      do: {:continue, input, target}

  def run(_decision, _context), do: {:error, :invalid_reasoning_decision}
end
