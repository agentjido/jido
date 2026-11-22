defmodule Jido.Examples.AI.Tools.Add do
  @moduledoc "Adds two numbers as one explicit Agent graph node."

  alias Jido.Joi

  use Jido.Action,
    id: "jido.ai/examples/tools/add",
    name: "add",
    description: "Add two numbers.",
    schema: Joi.object(%{left: Joi.number(), right: Joi.number()}),
    output_schema: Joi.object(%{value: Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left + right}}
end

defmodule Jido.Examples.AI.Tools.Multiply do
  @moduledoc "Multiplies two numbers as one explicit Agent graph node."

  alias Jido.Joi

  use Jido.Action,
    id: "jido.ai/examples/tools/multiply",
    name: "multiply",
    description: "Multiply two numbers.",
    schema: Joi.object(%{left: Joi.number(), right: Joi.number()}),
    output_schema: Joi.object(%{value: Joi.number()})

  @impl Jido.Action
  def run(%{left: left, right: right}, _context), do: {:ok, %{value: left * right}}
end
