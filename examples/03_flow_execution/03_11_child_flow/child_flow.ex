defmodule Jido.Examples.Execution.ChildFlow.Add do
  use Jido.Action, name: "example_exec_child_add"
  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}, [:child_effect]}
end

defmodule Jido.Examples.Execution.ChildFlow.Child do
  use Jido.Flow, name: "example_exec_child"
  alias Jido.Examples.Execution.ChildFlow.Add

  flow do
    step "add", action: Add, params: %{value: input(:value)}
    output result("add")
  end
end

defmodule Jido.Examples.Execution.ChildFlow do
  use Jido.Flow, name: "example_exec_child_parent"
  alias Jido.Examples.Execution.ChildFlow.Child

  flow do
    step "child", action: Child, params: %{value: input(:value)}
    output result("child")
  end
end
