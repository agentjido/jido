defmodule Jido.Examples.Execution.Parallel.Double do
  use Jido.Action, name: "example_exec_parallel_double"

  @impl true
  def run(%{value: value}, _context), do: {:ok, %{value: value * 2}}
end

defmodule Jido.Examples.Execution.Parallel do
  use Jido.Flow, name: "example_exec_parallel"
  alias Jido.Examples.Execution.Parallel.Double

  flow do
    parallel "checks" do
      action "left", Double, params: %{value: input(:left)}
      action "middle", Double, params: %{value: input(:middle)}
      action "right", Double, params: %{value: input(:right)}
    end

    output %{checks: result("checks")}
  end
end
