defmodule Jido.Examples.Execution.MapReduce.Double do
  use Jido.Action, name: "example_exec_map_reduce_double"
  @impl true
  def run(%{value: value, index: index}, _context), do: {:ok, %{value: value * 2, index: index}}
end

defmodule Jido.Examples.Execution.MapReduce.Sum do
  use Jido.Action, name: "example_exec_map_reduce_sum"
  @impl true
  def run(%{total: total, value: value}, _context), do: {:ok, %{total: total + value}}
end

defmodule Jido.Examples.Execution.MapReduce do
  use Jido.Flow, name: "example_exec_map_reduce"
  alias Jido.Examples.Execution.MapReduce.{Double, Sum}

  flow do
    map "doubled", collection: input(:values), action: Double, params: %{value: item(), index: item_index()}

    reduce "total",
      collection: result("doubled"),
      initial: %{total: 0},
      action: Sum,
      params: %{total: accumulator(:total), value: item(:value)}

    output %{items: result("doubled"), total: result("total")}
  end
end
