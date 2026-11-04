defmodule Jido.Examples.Execution.ThreeStepFlow.AddOne do
  use Jido.Action,
    name: "example_exec_three_step_add_one",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(params, _context), do: {:ok, %{value: params.value + 1}}
end

defmodule Jido.Examples.Execution.ThreeStepFlow.Double do
  use Jido.Action,
    name: "example_exec_three_step_double",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  @impl true
  def run(params, _context), do: {:ok, %{value: params.value * 2}}
end

defmodule Jido.Examples.Execution.ThreeStepFlow.Receipt do
  use Jido.Action,
    name: "example_exec_three_step_receipt",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  @impl true
  def run(params, _context), do: {:ok, %{value: params.value, label: "value=#{params.value}"}}
end

defmodule Jido.Examples.Execution.ThreeStepFlow do
  use Jido.Flow,
    name: "example_exec_three_step_flow",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
    output_schema: Jido.Joi.object(%{value: Jido.Joi.integer(), label: Jido.Joi.string()})

  alias Jido.Examples.Execution.ThreeStepFlow.{AddOne, Double, Receipt}

  flow do
    step "add_one", action: AddOne, params: %{value: input(:value)}
    step "double", action: Double, params: %{value: result("add_one", :value)}
    step "receipt", action: Receipt, params: %{value: result("double", :value)}
    output result("receipt")
  end
end
