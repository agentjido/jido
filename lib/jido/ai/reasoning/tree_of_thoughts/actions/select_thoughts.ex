defmodule Jido.AI.Reasoning.TreeOfThoughts.Actions.SelectThoughts do
  @moduledoc "Selects the two highest-scoring thoughts and routes the next phase."

  use Jido.Action,
    id: "jido.ai/reasoning/tree-of-thoughts/actions/select-thoughts",
    vsn: 1,
    name: "jido_ai_tree_of_thoughts_select_thoughts",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{terminal: output}, _context), do: {:ok, %{kind: :complete, output: output}}

  def run(%{state: %{phase: :select} = state}, _context) do
    selected = state.thoughts |> Enum.sort_by(& &1.score, :desc) |> Enum.take(2)
    next = state |> Map.put(:selected, selected) |> Map.put(:phase, :synthesize)
    {:ok, %{kind: :model, input: next}}
  end

  def run(%{state: state}, _context), do: {:ok, %{kind: :model, input: state}}
end
