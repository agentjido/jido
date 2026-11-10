defmodule Jido.Examples.Execution.DynamicInvoke.Plan do
  use Jido.Action, name: "example_dynamic_invoke_plan"
  @impl true
  def run(%{request: "calculate"}, _context),
    do: {:ok, %{target: "calculate", arguments: %{value: 21}}}

  def run(%{request: request}, _context),
    do: {:ok, %{target: "search", arguments: %{query: request}}}
end

defmodule Jido.Examples.Execution.DynamicInvoke.Search do
  use Jido.Action, name: "example_dynamic_invoke_search"
  @impl true
  def run(%{query: query}, _context), do: {:ok, %{tool: "search", result: query}}
end

defmodule Jido.Examples.Execution.DynamicInvoke.Calculate do
  use Jido.Action, name: "example_dynamic_invoke_calculate"
  @impl true
  def run(%{value: value}, _context), do: {:ok, %{tool: "calculate", result: value * 2}}
end

defmodule Jido.Examples.Execution.DynamicInvoke.Expand do
  use Jido.Action, name: "example_dynamic_invoke_expand"
  alias Jido.Examples.Execution.DynamicInvoke.{Calculate, Search}
  @impl true
  def run(%{target: "calculate", arguments: arguments}, _context),
    do: {:continue, arguments, Calculate}

  def run(%{target: "search", arguments: arguments}, _context),
    do: {:continue, arguments, Search}
end

defmodule Jido.Examples.Execution.DynamicInvoke do
  use Jido.Flow, name: "example_dynamic_invoke"
  alias Jido.Examples.Execution.DynamicInvoke.{Expand, Plan}

  flow do
    invoke "tool", decision: Plan, expander: Expand, params: %{request: input(:request)}
    output result("tool")
  end
end
