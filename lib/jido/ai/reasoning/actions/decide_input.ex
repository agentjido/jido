defmodule Jido.AI.Reasoning.Actions.DecideInput do
  @moduledoc "Starts a guarded reasoning graph or returns a blocked terminal outcome."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/actions/decide-input",
    vsn: 1,
    name: "jido_ai_decide_input",
    description: "Route a guarded request into its reasoning graph",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, guard: %{allowed: true}}, _context),
    do: {:ok, %{kind: :model, input: %{turn: turn}}}

  def run(
        %{turn: turn, guard: %{allowed: false, reason_code: reason_code, reason: reason}},
        _context
      ) do
    {:ok, %{kind: :complete, output: %{turn: turn, result: Result.blocked(reason_code, reason)}}}
  end
end
