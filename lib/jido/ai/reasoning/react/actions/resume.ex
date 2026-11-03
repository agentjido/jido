defmodule Jido.AI.Reasoning.ReAct.Actions.Resume do
  alias Jido.Joi

  @moduledoc "Creates fixed-loop state after an approved tool round."

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/resume",
    vsn: 1,
    name: "jido_ai_react_resume",
    description: "Resume the fixed ReAct loop after tool review",
    schema: Joi.object(%{turn: Joi.any()}),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context),
    do: {:ok, %{decision: nil, done: false, turn: turn}}
end
