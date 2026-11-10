defmodule Jido.AI.Reasoning.Actions.DecideInput do
  alias Jido.Joi
  @moduledoc "Starts a guarded reasoning graph or returns a blocked terminal outcome."

  alias Jido.AI.Reasoning.Result

  use Jido.Action,
    id: "jido.ai/reasoning/actions/decide-input",
    vsn: 1,
    name: "jido_ai_decide_input",
    description: "Route a guarded request into its reasoning graph",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{turn: turn, guard: %{allowed: true}, target: target} = params, _context)
      when is_atom(target) and target not in [nil, true, false] do
    input = Map.merge(%{turn: turn}, Map.get(params, :continuation, %{}))
    {:ok, %{kind: :model, input: input, target: target}}
  end

  def run(
        %{turn: turn, guard: %{allowed: false, reason_code: reason_code, reason: reason}},
        _context
      ) do
    {:ok, %{kind: :complete, output: %{turn: turn, result: Result.blocked(reason_code, reason)}}}
  end
end
