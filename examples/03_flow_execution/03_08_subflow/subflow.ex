defmodule Jido.Examples.Execution.Subflow.Add do
  use Jido.Action, name: "example_exec_subflow_add"

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value + 1}}
end

defmodule Jido.Examples.Execution.Subflow.Child do
  use Jido.Flow, name: "example_exec_subflow_child"
  alias Jido.Examples.Execution.Subflow.Add

  flow do
    step "add", action: Add, params: %{value: input(:value)}
    output result("add")
  end
end

defmodule Jido.Examples.Execution.Subflow do
  use Jido.Flow, name: "example_exec_subflow_parent"
  alias Jido.Examples.Execution.Subflow.Child

  flow do
    step "child", action: Child, params: %{value: input(:value)}
    output result("child")
  end
end
