defmodule Jido.Examples.Execution.RunicRunner.Add do
  use Jido.Action, name: "example_exec_runic_runner_add"

  @impl true
  def run(%{value: value, amount: amount}, _context), do: {:ok, %{value: value + amount}}
end

defmodule Jido.Examples.Execution.RunicRunner do
  use Jido.Flow, name: "example_exec_runic_runner"
  alias Jido.Examples.Execution.RunicRunner.Add

  flow do
    step "first", action: Add, params: %{value: input(:value), amount: 1}
    step "left", action: Add, params: %{value: result("first", :value), amount: 10}
    step "right", action: Add, params: %{value: result("first", :value), amount: 20}
    output %{left: result("left"), right: result("right")}
  end
end
