defmodule Jido.Examples.Compilation.InputsAndOutput.Total do
  alias Jido.Joi

  use Jido.Action,
    name: "example_inputs_output_total",
    schema: Joi.object(%{left: Joi.integer(), right: Joi.integer()}),
    output_schema: Joi.object(%{total: Joi.integer()})

  @impl true
  def run(params, _context), do: {:ok, %{total: params.left + params.right}}
end

defmodule Jido.Examples.Compilation.InputsAndOutput do
  alias Jido.Joi

  use Jido.Flow,
    name: "example_inputs_and_output",
    schema: Joi.object(%{left: Joi.integer(), right: Joi.integer()}),
    output_schema: Joi.object(%{answer: Joi.integer()})

  alias Jido.Examples.Compilation.InputsAndOutput.Total

  flow do
    step "total",
      action: Total,
      params: %{left: input(:left), right: input(:right)}

    output %{answer: result("total", :total)}
  end
end
