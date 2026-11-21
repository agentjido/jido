defmodule Jido.Examples.Execution.Reduce.Add do
  use Jido.Action, name: "example_exec_reduce_add"

  @impl true
  def run(%{total: total, value: value}, _context), do: {:ok, %{total: total + value}}
end

defmodule Jido.Examples.Execution.Reduce do
  use Jido.Flow, name: "example_exec_reduce"
  alias Jido.Examples.Execution.Reduce.Add

  flow do
    reduce "total",
      collection: input(:values),
      initial: %{total: 0},
      action: Add,
      params: %{total: accumulator(:total), value: item()}

    output result("total")
  end
end
