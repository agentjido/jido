defmodule Jido.Examples.Compilation.InputsAndOutput.Total do
  use Jido.Action,
    name: "example_inputs_output_total",
    schema: Jido.Joi.object(%{left: Jido.Joi.integer(), right: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{total: Jido.Joi.integer()})

  @impl true
  def run(params, _context), do: {:ok, %{total: params.left + params.right}}
end

defmodule Jido.Examples.Compilation.InputsAndOutput do
  use Jido.Flow,
    name: "example_inputs_and_output",
    schema: Jido.Joi.object(%{left: Jido.Joi.integer(), right: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{answer: Jido.Joi.integer()})

  alias Jido.Examples.Compilation.InputsAndOutput.Total

  flow do
    step "total",
      action: Total,
      params: %{left: input(:left), right: input(:right)}

    output %{answer: result("total", :total)}
  end
end
