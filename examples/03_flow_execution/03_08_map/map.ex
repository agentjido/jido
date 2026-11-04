defmodule Jido.Examples.Execution.Map.Check do
  use Jido.Action, name: "example_exec_map_check"

  @impl true
  def run(%{value: value, index: index}, context) do
    if match?(%{observer: _, gate: _}, context) do
      send(context.observer, {:map_item_ready, index, self()})
      receive do: ({:release_map_item, gate} when gate == context.gate -> :ok)
    end

    if value < 0, do: {:error, :negative_value}, else: {:ok, %{index: index, value: value * 2}}
  end
end

defmodule Jido.Examples.Execution.Map do
  use Jido.Flow, name: "example_exec_map"
  alias Jido.Examples.Execution.Map.Check

  flow do
    map "items",
      collection: input(:values),
      action: Check,
      params: %{value: item(), index: item_index()},
      on_error: :collect_errors

    output %{items: result("items")}
  end
end
