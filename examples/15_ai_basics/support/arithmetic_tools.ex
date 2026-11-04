defmodule Jido.Examples.AI.Tools.Add do
  @moduledoc "Adds two numbers as one explicit Agent graph node."

  use Jido.Action,
    id: "jido.ai/examples/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Jido.Joi.object(%{left: Jido.Joi.number(), right: Jido.Joi.number()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule Jido.Examples.AI.Tools.Multiply do
  @moduledoc "Multiplies two numbers as one explicit Agent graph node."

  use Jido.Action,
    id: "jido.ai/examples/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Jido.Joi.object(%{left: Jido.Joi.number(), right: Jido.Joi.number()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end
