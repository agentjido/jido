defmodule Jido.AI.Reasoning.TreeOfThoughts.Actions.SelectThoughts do
  alias Jido.Joi
  @moduledoc "Selects the two highest-scoring thoughts and routes the next phase."

  use Jido.Action,
    id: "jido.ai/reasoning/tree-of-thoughts/actions/select-thoughts",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_select_thoughts",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{decision: %{terminal: output}}, _context),
    do: {:ok, %{kind: :complete, output: output}}

  def run(%{decision: %{state: %{phase: :select} = state}, target: target}, _context) do
    selected = state.thoughts |> Enum.sort_by(& &1.score, :desc) |> Enum.take(2)
    next = state |> Map.put(:selected, selected) |> Map.put(:phase, :synthesize)
    {:ok, %{kind: :model, input: next, target: target}}
  end

  def run(%{decision: %{state: state}, target: target}, _context),
    do: {:ok, %{kind: :model, input: state, target: target}}
end
