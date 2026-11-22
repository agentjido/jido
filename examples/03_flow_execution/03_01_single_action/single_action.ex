defmodule Jido.Examples.Execution.SingleAction.Add do
  alias Jido.Joi

  use Jido.Action,
    name: "example_exec_single_action_add",
    schema: Joi.object(%{value: Joi.integer(), amount: Joi.integer()}),
    output_schema: Joi.object(%{value: Joi.integer()})

  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end
