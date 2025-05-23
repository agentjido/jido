defmodule JidoTest.Signal.Bus.RecordedSignalSerializationTest do
  use ExUnit.Case, async: false
  alias Jido.Signal
  alias Jido.Signal.Bus.RecordedSignal

  describe "RecordedSignal.serialize/1" do
    test "serializes a simple recorded signal" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123"
      }

      recorded = %RecordedSignal{
        id: "record-123",
        type: "test.event",
        created_at: DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC"),
        signal: signal
      }

      json = RecordedSignal.serialize(recorded)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert decoded["id"] == "record-123"
      assert decoded["type"] == "test.event"
      assert decoded["created_at"] == "2023-01-01T12:00:00Z"
      assert decoded["signal"]["type"] == "test.event"
      assert decoded["signal"]["source"] == "/test/source"
      assert decoded["signal"]["id"] == "test-id-123"
    end

    test "serializes a list of recorded signals" do
      signal1 = %Signal{type: "first.event", source: "/test/first", id: "first-id"}
      signal2 = %Signal{type: "second.event", source: "/test/second", id: "second-id"}

      records = [
        %RecordedSignal{
          id: "record-1",
          type: "first.event",
          created_at: DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC"),
          signal: signal1
        },
        %RecordedSignal{
          id: "record-2",
          type: "second.event",
          created_at: DateTime.from_naive!(~N[2023-01-01 13:00:00], "Etc/UTC"),
          signal: signal2
        }
      ]

      json = RecordedSignal.serialize(records)
      assert is_binary(json)

      decoded = Jason.decode!(json)
      assert length(decoded) == 2
      assert Enum.at(decoded, 0)["id"] == "record-1"
      assert Enum.at(decoded, 1)["id"] == "record-2"
      assert Enum.at(decoded, 0)["signal"]["type"] == "first.event"
      assert Enum.at(decoded, 1)["signal"]["type"] == "second.event"
    end
  end

  describe "RecordedSignal.deserialize/1" do
    test "deserializes a simple recorded signal" do
      json = ~s({
        "id": "record-123",
        "type": "test.event",
        "created_at": "2023-01-01T12:00:00Z",
        "signal": {
          "type": "test.event",
          "source": "/test/source",
          "id": "test-id-123",
          "specversion": "1.0.2"
        }
      })

      {:ok, recorded} = RecordedSignal.deserialize(json)
      assert %RecordedSignal{} = recorded
      assert recorded.id == "record-123"
      assert recorded.type == "test.event"
      assert recorded.created_at == DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC")
      assert recorded.signal.type == "test.event"
      assert recorded.signal.source == "/test/source"
      assert recorded.signal.id == "test-id-123"
    end

    test "deserializes a list of recorded signals" do
      json = ~s([
        {
          "id": "record-1",
          "type": "first.event",
          "created_at": "2023-01-01T12:00:00Z",
          "signal": {
            "type": "first.event",
            "source": "/test/first",
            "id": "first-id",
            "specversion": "1.0.2"
          }
        },
        {
          "id": "record-2",
          "type": "second.event",
          "created_at": "2023-01-01T13:00:00Z",
          "signal": {
            "type": "second.event",
            "source": "/test/second",
            "id": "second-id",
            "specversion": "1.0.2"
          }
        }
      ])

      {:ok, records} = RecordedSignal.deserialize(json)
      assert is_list(records)
      assert length(records) == 2

      first = Enum.at(records, 0)
      second = Enum.at(records, 1)

      assert first.id == "record-1"
      assert second.id == "record-2"
      assert first.signal.type == "first.event"
      assert second.signal.type == "second.event"
    end

    test "returns error for invalid JSON" do
      json = ~s({"id":"broken")

      result = RecordedSignal.deserialize(json)
      assert {:error, _reason} = result
    end

    test "returns error for invalid recorded signal structure" do
      json = ~s({"not_a_recorded_signal":"test"})

      result = RecordedSignal.deserialize(json)
      assert {:error, _reason} = result
    end
  end

  describe "round-trip serialization" do
    test "preserves recorded signal data through serialization and deserialization" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        subject: "test-subject",
        data: %{
          "string" => "value",
          "number" => 42,
          "boolean" => true
        }
      }

      original = %RecordedSignal{
        id: "record-123",
        type: "test.event",
        created_at: DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC"),
        signal: signal
      }

      json = RecordedSignal.serialize(original)
      {:ok, deserialized} = RecordedSignal.deserialize(json)

      assert deserialized.id == original.id
      assert deserialized.type == original.type

      assert DateTime.to_iso8601(deserialized.created_at) ==
               DateTime.to_iso8601(original.created_at)

      assert deserialized.signal.type == original.signal.type
      assert deserialized.signal.source == original.signal.source
      assert deserialized.signal.id == original.signal.id
      assert deserialized.signal.subject == original.signal.subject
      assert deserialized.signal.data["string"] == original.signal.data["string"]
      assert deserialized.signal.data["number"] == original.signal.data["number"]
      assert deserialized.signal.data["boolean"] == original.signal.data["boolean"]
    end

    test "preserves list of recorded signals through serialization and deserialization" do
      signal1 = %Signal{type: "first.event", source: "/test/first", id: "first-id"}
      signal2 = %Signal{type: "second.event", source: "/test/second", id: "second-id"}

      originals = [
        %RecordedSignal{
          id: "record-1",
          type: "first.event",
          created_at: DateTime.from_naive!(~N[2023-01-01 12:00:00], "Etc/UTC"),
          signal: signal1
        },
        %RecordedSignal{
          id: "record-2",
          type: "second.event",
          created_at: DateTime.from_naive!(~N[2023-01-01 13:00:00], "Etc/UTC"),
          signal: signal2
        }
      ]

      json = RecordedSignal.serialize(originals)
      {:ok, deserialized} = RecordedSignal.deserialize(json)

      assert length(deserialized) == length(originals)

      Enum.zip(originals, deserialized)
      |> Enum.each(fn {original, deserialized} ->
        assert deserialized.id == original.id
        assert deserialized.type == original.type

        assert DateTime.to_iso8601(deserialized.created_at) ==
                 DateTime.to_iso8601(original.created_at)

        assert deserialized.signal.type == original.signal.type
        assert deserialized.signal.source == original.signal.source
        assert deserialized.signal.id == original.signal.id
      end)
    end
  end
end
