defmodule Jido.Examples.Execution.Reduce.Add do
  use Jido.Action, name: "example_exec_reduce_add"
  @impl true
  def run(%{total: total, value: value, index: index}, context) do
    if observer = context[:observer], do: send(observer, {:reduce_item, index, total, value})
    {:ok, %{total: total + value}, [{:reduced, index}]}
  end
end

defmodule Jido.Examples.Execution.Reduce do
  use Jido.Flow, name: "example_exec_reduce"
  alias Jido.Examples.Execution.Reduce.Add

  flow do
    reduce "total",
      collection: input(:values),
      initial: %{total: 0},
      action: Add,
      params: %{total: accumulator(:total), value: item(), index: item_index()}

    output result("total")
  end
end
