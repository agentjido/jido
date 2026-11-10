defmodule Jido.Examples.Patterns.BatchProcessing.Normalize do
  use Jido.Action, name: "example_batch_normalize"

  @impl true
  def run(%{value: value, index: index}, context) do
    coordinate(index, context)
    {:ok, %{value: value * 2, index: index}}
  end

  defp coordinate(index, %{gate: gate, observer: observer}) do
    send(observer, {:batch_ready, index, self()})

    receive do
      {:release_batch, ^gate} -> :ok
    end
  end

  defp coordinate(_index, _context), do: :ok
end

defmodule Jido.Examples.Patterns.BatchProcessing.Total do
  use Jido.Action, name: "example_batch_total"

  @impl true
  def run(%{total: total, item: item}, _context), do: {:ok, %{total: total + item.value}}
end

defmodule Jido.Examples.Patterns.BatchProcessing do
  use Jido.Flow, name: "example_batch_processing"

  alias Jido.Examples.Patterns.BatchProcessing.{Normalize, Total}

  flow do
    map "items",
      collection: input(:items),
      action: Normalize,
      params: %{value: item(), index: item_index()}

    reduce "total",
      collection: result("items"),
      initial: %{total: 0},
      action: Total,
      params: %{total: accumulator(:total), item: item()}

    output %{items: result("items"), total: result("total")}
  end
end
