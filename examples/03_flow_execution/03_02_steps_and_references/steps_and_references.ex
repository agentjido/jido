defmodule Jido.Examples.Execution.StepsAndReferences.AddOne do
  use Jido.Action, name: "example_exec_steps_add_one"

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule Jido.Examples.Execution.StepsAndReferences.Double do
  use Jido.Action, name: "example_exec_steps_double"

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value * 2}}
end

defmodule Jido.Examples.Execution.StepsAndReferences.Label do
  use Jido.Action, name: "example_exec_steps_label"

  @impl true
  def run(%{value: value, prefix: prefix}, _context),
    do: {:ok, %{value: value, label: "#{prefix}=#{value}"}}
end

defmodule Jido.Examples.Execution.StepsAndReferences do
  use Jido.Flow,
    name: "example_exec_steps_and_references",
    schema: Jido.Joi.object(%{value: Jido.Joi.integer()})

  alias Jido.Examples.Execution.StepsAndReferences.{AddOne, Double, Label}

  flow do
    step "add_one", action: AddOne, params: %{value: input(:value)}
    step "double", action: Double, params: %{value: result("add_one", :value)}

    step "label",
      action: Label,
      params: %{value: result("double", :value), prefix: context(:prefix)}

    output result("label")
  end
end
