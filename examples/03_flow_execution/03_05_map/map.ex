defmodule Jido.Examples.Execution.Map.DoublePositive do
  use Jido.Action, name: "example_exec_map_double_positive"

  @impl true
  def run(%{value: value, index: index}, _context) when value >= 0,
    do: {:ok, %{index: index, value: value * 2}}

  def run(%{value: value}, _context), do: {:error, "negative value: #{value}"}
end

defmodule Jido.Examples.Execution.Map do
  use Jido.Flow, name: "example_exec_map"
  alias Jido.Examples.Execution.Map.DoublePositive

  flow do
    map "items",
      collection: input(:values),
      action: DoublePositive,
      params: %{value: item(), index: item_index()},
      on_error: :collect_errors

    output %{items: result("items")}
  end
end
