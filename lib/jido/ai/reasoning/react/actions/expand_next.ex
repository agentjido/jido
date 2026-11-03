defmodule Jido.AI.Reasoning.ReAct.Actions.ExpandNext do
  alias Jido.Joi
  @moduledoc "Expands each trusted AI routing decision into its next executable."

  alias Jido.AI.Reasoning.ReAct.ToolRound

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/expand-next",
    vsn: 1,
    name: "jido_ai_react_expand_next",
    description: "Expand a trusted AI graph routing decision",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{kind: :complete, output: output}, _context), do: {:ok, output}

  def run(%{kind: :model, input: input, target: target}, _context),
    do: {:continue, input, target}

  def run(%{kind: :review, input: input, target: target}, _context),
    do: {:continue, input, target}

  def run(%{kind: :tools, input: %{turn: turn} = input, target: target}, context) do
    with {:ok, flow} <- ToolRound.build(turn, context, continuation: target) do
      {:continue, input, flow}
    end
  end

  def run(%{kind: :tools}, _context), do: {:error, :invalid_tool_calls}
end
