defmodule Jido.Signal.Bus.Store.MemoryTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Bus.Store.Memory

  test "keeps a bounded ordered record log and its latest cursor" do
    assert {:ok, state} = Memory.init(max_records: 2)
    records = [record(1, "one"), record(2, "two"), record(3, "three")]

    assert {:ok, state} = Memory.append(records, state)
    assert {:ok, [second, third]} = Memory.read([after_cursor: 0], state)
    assert second["id"] == "two"
    assert third["id"] == "three"
    assert {:ok, [^third]} = Memory.read([after_cursor: 2], state)
    assert {:ok, 3} = Memory.latest_cursor(state)
  end

  test "keeps durable subscription definitions in creation order" do
    assert {:ok, state} = Memory.init([])

    assert {:ok, state} =
             Memory.append(
               [record(1, "one"), record(2, "two"), record(3, "three"), record(4, "four")],
               state
             )

    first = subscription("first", "orders.*", 2)
    second = subscription("second", "audit.**", 4)

    assert {:ok, state} = Memory.put_subscription(first, state)
    assert {:ok, state} = Memory.put_subscription(second, state)
    assert {:ok, [^first, ^second]} = Memory.list_subscriptions(state)

    updated = %{first | "cursor" => 3}
    assert {:ok, state} = Memory.put_subscription(updated, state)
    assert {:ok, [^updated, ^second]} = Memory.list_subscriptions(state)

    assert {:ok, state} = Memory.delete_subscription("first", state)
    assert {:ok, [^second]} = Memory.list_subscriptions(state)
  end

  test "does not remove a record that an unacknowledged durable subscription needs" do
    assert {:ok, state} = Memory.init(max_records: 2)
    assert {:ok, state} = Memory.put_subscription(subscription("agent", "orders.*", 0), state)
    assert {:ok, state} = Memory.append([record(1, "one"), record(2, "two")], state)

    assert {:error, {:store_full, ["agent"]}} = Memory.append([record(3, "three")], state)
    assert {:ok, [first, second]} = Memory.read([after_cursor: 0], state)
    assert Enum.map([first, second], & &1["cursor"]) == [1, 2]
    assert {:ok, 2} = Memory.latest_cursor(state)
  end

  test "releases acknowledged records" do
    assert {:ok, state} = Memory.init(max_records: 2)
    definition = subscription("agent", "orders.*", 0)
    assert {:ok, state} = Memory.put_subscription(definition, state)
    assert {:ok, state} = Memory.append([record(1, "one"), record(2, "two")], state)

    assert {:ok, state} = Memory.put_subscription(%{definition | "cursor" => 1}, state)
    assert {:ok, state} = Memory.append([record(3, "three")], state)
    assert {:ok, records} = Memory.read([after_cursor: 0], state)
    assert Enum.map(records, & &1["cursor"]) == [2, 3]
  end

  test "reports sorted blockers and excludes acknowledged or unrelated subscriptions" do
    assert {:ok, state} = Memory.init(max_records: 2)
    records = [Map.put(record(1, "one"), "type", "orders.special"), record(2, "two")]
    assert {:ok, state} = Memory.append(records, state)

    state =
      Enum.reduce(
        [
          subscription("z-agent", "orders.*", 0),
          subscription("a-agent", "orders.**", 1),
          subscription("acknowledged", "orders.special", 2),
          subscription("unrelated", "metrics.**", 0)
        ],
        state,
        fn definition, state ->
          assert {:ok, state} = Memory.put_subscription(definition, state)
          state
        end
      )

    assert {:error, {:store_full, ["a-agent", "z-agent"]}} =
             Memory.append([record(3, "three"), record(4, "four")], state)

    assert {:ok, ^records} = Memory.read([], state)
    assert {:ok, 2} = Memory.latest_cursor(state)
  end

  test "rejects invalid bounds and non-contiguous cursors" do
    assert {:error, {:invalid_option, :max_records}} = Memory.init(max_records: 0)
    assert {:ok, state} = Memory.init([])
    assert {:error, :invalid_record_cursors} = Memory.append([record(2, "two")], state)

    assert {:error, :invalid_subscription_cursor} =
             Memory.put_subscription(subscription("future", "orders.*", 1), state)
  end

  test "validates append and read boundaries" do
    assert {:ok, state} = Memory.init([])
    assert {:ok, unchanged} = Memory.append([], state)
    assert unchanged == state
    assert {:error, :invalid_records} = Memory.append(:invalid, state)
    assert {:error, :invalid_records} = Memory.append([record(1, "one") | :tail], state)
    assert {:ok, 0} = Memory.latest_cursor(state)

    invalid_record = Map.delete(record(1, "invalid"), "type")
    assert {:error, :invalid_records} = Memory.append([invalid_record], state)

    for invalid <- [nil, :invalid, 12, {:invalid}, []] do
      assert {:error, :invalid_records} = Memory.append([invalid], state)
      assert {:ok, 0} = Memory.latest_cursor(state)
    end

    assert {:ok, state} = Memory.append([record(1, "one")], state)
    assert {:ok, []} = Memory.read([after_cursor: 0, path: "audit.*"], state)
    assert {:error, :invalid_read_options} = Memory.read([limit: 0], state)
  end

  test "rejects invalid and conflicting subscription updates" do
    assert {:ok, state} = Memory.init([])
    assert {:error, :invalid_subscription} = Memory.put_subscription(%{}, state)

    assert {:ok, state} = Memory.append([record(1, "one")], state)
    original = subscription("agent", "orders.*", 1)
    assert {:ok, state} = Memory.put_subscription(original, state)

    assert {:error, :subscription_conflict} =
             Memory.put_subscription(%{original | "path" => "audit.*"}, state)

    assert {:error, :subscription_conflict} =
             Memory.put_subscription(%{original | "created_at" => "2026-01-02T00:00:00Z"}, state)

    assert {:error, :cursor_regression} =
             Memory.put_subscription(%{original | "cursor" => 0}, state)
  end

  test "filters replay before applying the limit and keeps invalid patterns empty" do
    assert {:ok, state} = Memory.init([])

    records = [
      record(1, "first"),
      Map.put(record(2, "audit"), "type", "audit.saved"),
      record(3, "third"),
      record(4, "fourth")
    ]

    assert {:ok, state} = Memory.append(records, state)

    for path <- ["orders.created", "orders.*", "orders.**", "**.created"] do
      assert {:ok, [result]} = Memory.read([after_cursor: 1, path: path, limit: 1], state)
      assert result["cursor"] == 3
    end

    for path <- ["", "orders..created", "**.**", "orders.invalid*", "absent.*"] do
      assert {:ok, []} = Memory.read([path: path], state)
    end

    assert {:error, :invalid_read_options} = Memory.read([path: "**.**", limit: 0], state)
  end

  test "replay preserves exact, single, and multiple globstar matching" do
    types = [
      "orders",
      "orders.created",
      "orders.eu.created",
      "audit",
      "audit.eu.created",
      "orders.created.extra"
    ]

    records =
      for {type, cursor} <- Enum.with_index(types, 1),
          do: Map.put(record(cursor, "r#{cursor}"), "type", type)

    assert {:ok, state} = Memory.init([])
    assert {:ok, state} = Memory.append(records, state)

    for {path, cursors} <- [
          {"orders", [1]},
          {"orders.*", [2]},
          {"orders.**", [1, 2, 3, 6]},
          {"**.created", [2, 3, 5]},
          {"**.eu.**", [3, 5]},
          {"**.orders.**.created.**", [2, 3, 6]}
        ] do
      assert {:ok, found} = Memory.read([path: path], state)
      assert Enum.map(found, & &1["cursor"]) == cursors
      assert {:ok, limited} = Memory.read([path: path, after_cursor: 1, limit: 2], state)
      assert Enum.map(limited, & &1["cursor"]) == Enum.take(Enum.filter(cursors, &(&1 > 1)), 2)
    end
  end

  test "trims large bursts after the last durable subscription is deleted" do
    assert {:ok, state} = Memory.init(max_records: 3)
    assert {:ok, state} = Memory.put_subscription(subscription("pin", "orders.**", 0), state)
    initial = for cursor <- 1..3, do: record(cursor, "r#{cursor}")
    assert {:ok, state} = Memory.append(initial, state)
    assert {:error, {:store_full, ["pin"]}} = Memory.append([record(4, "r4")], state)
    assert {:ok, ^initial} = Memory.read([], state)
    assert {:ok, state} = Memory.delete_subscription("pin", state)
    burst = for cursor <- 4..12, do: record(cursor, "r#{cursor}")
    assert {:ok, state} = Memory.append(burst, state)
    assert {:ok, 12} = Memory.latest_cursor(state)
    assert {:ok, retained} = Memory.read([], state)
    assert length(retained) == 3
    assert Enum.map(retained, & &1["cursor"]) == [10, 11, 12]
    assert {:ok, ^state} = Memory.append([], state)
    assert {:ok, state} = Memory.append([record(13, "r13")], state)
    assert {:ok, retained} = Memory.read([], state)
    assert Enum.map(retained, & &1["cursor"]) == [11, 12, 13]
  end

  defp record(cursor, id) do
    %{
      "format_version" => 1,
      "id" => id,
      "cursor" => cursor,
      "type" => "orders.created",
      "created_at" => "2026-01-01T00:00:00Z",
      "signal" => %{"id" => id, "type" => "orders.created"}
    }
  end

  defp subscription(id, path, cursor) do
    %{
      "format_version" => 1,
      "id" => id,
      "path" => path,
      "cursor" => cursor,
      "created_at" => "2026-01-01T00:00:00Z"
    }
  end
end
