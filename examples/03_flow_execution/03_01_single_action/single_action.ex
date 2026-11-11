defmodule Jido.Examples.Execution.SingleAction.Add do
  use Jido.Action,
    name: "example_exec_single_action_add",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer(), amount: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end
