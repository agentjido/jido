defmodule Jido.Examples.Execution.ControlledExecution.Add do
  use Jido.Action, name: "example_exec_controlled_add"
  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end

defmodule Jido.Examples.Execution.ControlledExecution do
  use Jido.Flow, name: "example_exec_controlled"
  alias Jido.Examples.Execution.ControlledExecution.Add

  flow do
    step "first", action: Add, params: %{value: input(:value), amount: 1}
    step "left", action: Add, params: %{value: result("first", :value), amount: 10}
    step "right", action: Add, params: %{value: result("first", :value), amount: 20}
    output %{left: result("left"), right: result("right")}
  end
end
