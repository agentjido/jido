defmodule Jido.Signal.Bus.RecordedSignalTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal.Bus.RecordedSignal

  test "builds ordered stored and public records" do
    first = signal("orders.created", %{id: 1})
    second = signal("orders.updated", %{id: 1})

    {:ok, stored, entries, next_cursor} = RecordedSignal.build([first, second], 4)

    assert Enum.map(stored, & &1["cursor"]) == [4, 5]
    assert Enum.map(stored, & &1["type"]) == ["orders.created", "orders.updated"]

    assert Enum.map(entries, fn {_stored, source, public} -> {source, public.cursor} end) == [
             {first, 4},
             {second, 5}
           ]

    assert next_cursor == 6
  end

  test "decodes stored records in order" do
    signals = [signal("orders.created"), signal("orders.updated")]
    {:ok, stored, _entries, _next_cursor} = RecordedSignal.build(signals, 1)

    assert {:ok, decoded} = RecordedSignal.decode(stored)
    assert Enum.map(decoded, & &1.cursor) == [1, 2]
    assert Enum.map(decoded, & &1.signal.type) == ["orders.created", "orders.updated"]
    assert Enum.all?(decoded, &match?(%DateTime{}, &1.created_at))
  end

  test "rejects unsupported and malformed stored records" do
    assert {:error, :unsupported_store_record} = RecordedSignal.from_record(%{})

    malformed = %{
      "format_version" => 1,
      "id" => "record-1",
      "cursor" => 1,
      "type" => "orders.created",
      "created_at" => "not-a-time",
      "signal" => %{}
    }

    assert {:error, :invalid_store_record} = RecordedSignal.from_record(malformed)
    assert {:error, :invalid_store_record} = RecordedSignal.decode([malformed])

    assert {:ok, stored, _entries, _next_cursor} =
             RecordedSignal.build([signal("orders.created")], 1)

    [record] = stored

    assert {:error, :invalid_store_record} =
             RecordedSignal.from_record(%{record | "type" => "orders.different"})

    assert {:error, :invalid_store_record} =
             RecordedSignal.from_record(%{
               record
               | "signal" => Map.put(record["signal"], {:tuple, :key}, "invalid")
             })
  end

  test "rejects malformed Signal structs without raising" do
    malformed = %Jido.Signal{
      id: "bad",
      source: "/test",
      type: "orders.created",
      extensions: :invalid
    }

    assert {:error, {:invalid_signal, 0, _reason}} = RecordedSignal.build([malformed], 1)

    valid = signal("orders.created")
    malformed_extensions = %{valid | extensions: %{{:tuple, :key} => "invalid"}}

    assert {:error, {:invalid_signal, 0, _reason}} =
             RecordedSignal.build([malformed_extensions], 1)
  end

  test "exposes a schema for public record values" do
    signal = signal("orders.created")

    {:ok, _stored, [{_record, ^signal, public}], _next_cursor} =
      RecordedSignal.build([signal], 1)

    assert {:ok, ^public} = Zoi.parse(RecordedSignal.schema(), public)
  end
end
