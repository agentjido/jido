defmodule Jido.AI.Reasoning.ReAct.Actions.FinishLoop do
  alias Jido.Joi

  @moduledoc "Returns the terminal or review decision from the fixed ReAct loop."

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/finish-loop",
    vsn: 1,
    name: "jido_ai_react_finish_loop",
    description: "Finish or suspend the fixed ReAct loop",
    schema: Joi.object(%{state: Joi.map()}),
    output_schema: Joi.map()

  @impl Jido.Action
  def run(%{state: %{done: true, decision: decision}}, _context) when is_map(decision),
    do: {:ok, decision}

  def run(_params, _context), do: {:error, :incomplete_react_loop}
end
