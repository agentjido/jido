defmodule Jido.Examples.ProgressObservation.Buffer do
  @moduledoc "A bounded, demand-read progress buffer for one producer."
  use GenServer

  def start_link(capacity), do: GenServer.start_link(__MODULE__, capacity)
  def table(pid), do: GenServer.call(pid, :table)

  @impl true
  def init(capacity) when is_integer(capacity) and capacity > 0 do
    table = :ets.new(__MODULE__, [:set, :public])
    :ets.insert(table, [{:sequence, 0}, {:capacity, capacity}])
    {:ok, table}
  end

  @impl true
  def handle_call(:table, _from, table), do: {:reply, table, table}

  def publish(table, progress) do
    capacity = :ets.lookup_element(table, :capacity, 2)
    sequence = :ets.update_counter(table, :sequence, 1)
    :ets.insert(table, {rem(sequence, capacity), sequence, progress})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def read(table, cursor) do
    events =
      for {slot, sequence, value} <- :ets.tab2list(table), is_integer(slot), sequence > cursor do
        {sequence, value}
      end
      |> Enum.sort()

    missed =
      case events do
        [{first, _value} | _rest] -> max(first - cursor - 1, 0)
        [] -> 0
      end

    %{
      events: events,
      missed: missed,
      cursor:
        case List.last(events) do
          nil -> cursor
          {last, _value} -> last
        end
    }
  rescue
    ArgumentError -> %{events: [], missed: :buffer_lost, cursor: cursor}
  end
end
