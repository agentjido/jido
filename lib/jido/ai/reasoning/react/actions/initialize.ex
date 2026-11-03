defmodule Jido.AI.Reasoning.ReAct.Actions.Initialize do
  alias Jido.AI.Reasoning.Result
  alias Jido.Joi

  @moduledoc "Creates the bounded state for the fixed ReAct loop."

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/initialize",
    vsn: 1,
    name: "jido_ai_react_initialize",
    description: "Initialize the fixed ReAct loop",
    schema: Joi.map(),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{turn: turn, guard: %{allowed: true}}, _context) do
    {:ok, %{decision: nil, done: false, turn: turn}}
  end

  def run(
        %{turn: turn, guard: %{allowed: false, reason_code: reason_code, reason: reason}},
        _context
      ) do
    decision = %{
      kind: :complete,
      output: %{turn: turn, result: Result.blocked(reason_code, reason)}
    }

    {:ok, %{decision: decision, done: true, turn: turn}}
  end
end
