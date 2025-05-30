defmodule Jido.Signal.SerializationStrategiesTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Serialization.{JsonSerializer, ErlangTermSerializer, MsgpackSerializer}

  @serializers [
    {"JSON", JsonSerializer},
    {"Erlang Term", ErlangTermSerializer},
    {"MessagePack", MsgpackSerializer}
  ]

  describe "Signal serialization with different strategies" do
    test "all serializers can handle basic Signal" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123"
      }

      for {_name, serializer} <- @serializers do
        {:ok, binary} = Signal.serialize(signal, serializer: serializer)
        assert is_binary(binary)

        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)
        assert %Signal{} = deserialized
        assert deserialized.type == signal.type
        assert deserialized.source == signal.source
        assert deserialized.id == signal.id
      end
    end

    test "all serializers can handle Signal with data" do
      signal = %Signal{
        type: "test.event",
        source: "/test/source",
        id: "test-id-123",
        data: %{
          "message" => "hello world",
          "count" => 42,
          "active" => true,
          "metadata" => %{"version" => "1.0"}
        }
      }

      for {_name, serializer} <- @serializers do
        {:ok, binary} = Signal.serialize(signal, serializer: serializer)
        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)

        assert deserialized.type == signal.type
        assert deserialized.source == signal.source
        assert deserialized.id == signal.id

        # Data comparison might vary by serializer due to type preservation differences
        case serializer do
          ErlangTermSerializer ->
            # Erlang terms preserve exact types
            assert deserialized.data == signal.data

          JsonSerializer ->
            # JSON preserves structure but string keys
            assert deserialized.data["message"] == "hello world"
            assert deserialized.data["count"] == 42
            assert deserialized.data["active"] == true
            assert deserialized.data["metadata"]["version"] == "1.0"

          MsgpackSerializer ->
            # MessagePack preserves structure but converts atoms to strings
            assert deserialized.data["message"] == "hello world"
            assert deserialized.data["count"] == 42
            assert deserialized.data["active"] == true
            assert deserialized.data["metadata"]["version"] == "1.0"
        end
      end
    end

    test "all serializers can handle Signal lists" do
      signals = [
        %Signal{type: "first.event", source: "/test/first", id: "first-id"},
        %Signal{type: "second.event", source: "/test/second", id: "second-id"}
      ]

      for {_name, serializer} <- @serializers do
        {:ok, binary} = Signal.serialize(signals, serializer: serializer)
        assert is_binary(binary)

        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)
        assert is_list(deserialized)
        assert length(deserialized) == 2

        first = Enum.at(deserialized, 0)
        second = Enum.at(deserialized, 1)

        assert first.type == "first.event"
        assert second.type == "second.event"
      end
    end

    test "all serializers handle full Signal structure" do
      signal = %Signal{
        type: "complex.event",
        source: "/complex/source",
        id: "complex-id-123",
        subject: "test-subject",
        time: "2023-01-01T12:00:00Z",
        datacontenttype: "application/json",
        dataschema: "https://example.com/schema",
        data: %{
          "nested" => %{
            "deep" => %{"value" => 42}
          },
          "list" => [1, 2, 3],
          "mixed" => %{
            "string" => "text",
            "number" => 3.14,
            "boolean" => false
          }
        }
      }

      for {_name, serializer} <- @serializers do
        {:ok, binary} = Signal.serialize(signal, serializer: serializer)
        {:ok, deserialized} = Signal.deserialize(binary, serializer: serializer)

        # Verify all required fields
        assert deserialized.type == signal.type
        assert deserialized.source == signal.source
        assert deserialized.id == signal.id
        assert deserialized.subject == signal.subject
        assert deserialized.time == signal.time
        assert deserialized.datacontenttype == signal.datacontenttype
        assert deserialized.dataschema == signal.dataschema

        # Verify data structure is preserved (with type variations)
        assert deserialized.data["list"] == [1, 2, 3]

        case serializer do
          ErlangTermSerializer ->
            assert deserialized.data == signal.data

          _ ->
            # JSON and MessagePack preserve structure but may convert types
            assert deserialized.data["nested"]["deep"]["value"] == 42
            assert deserialized.data["mixed"]["string"] == "text"
            assert deserialized.data["mixed"]["number"] == 3.14
            assert deserialized.data["mixed"]["boolean"] == false
        end
      end
    end

    test "serializer size comparison" do
      signal = %Signal{
        type: "benchmark.event",
        source: "/benchmark/source",
        id: "benchmark-id-123",
        data: %{
          "message" => "This is a test message for size comparison",
          "numbers" => Enum.to_list(1..100),
          "metadata" => %{
            "created_at" => "2023-01-01T12:00:00Z",
            "version" => "1.0.0",
            "tags" => ["test", "benchmark", "comparison"]
          }
        }
      }

      sizes =
        for {name, serializer} <- @serializers do
          {:ok, binary} = Signal.serialize(signal, serializer: serializer)
          {name, byte_size(binary)}
        end

      # Verify all serializers produce some output
      for {name, size} <- sizes do
        assert size > 0, "#{name} should produce non-empty output"
      end
    end

    test "serialization performance comparison" do
      signal = %Signal{
        type: "performance.test",
        source: "/perf/test",
        id: "perf-123",
        data: %{
          "payload" => String.duplicate("x", 1000),
          "list" => Enum.to_list(1..500)
        }
      }

      for {_name, serializer} <- @serializers do
        # Warm up
        Signal.serialize(signal, serializer: serializer)

        # Time serialization
        {serialize_time, {:ok, binary}} =
          :timer.tc(fn -> Signal.serialize(signal, serializer: serializer) end)

        # Time deserialization
        {deserialize_time, {:ok, _result}} =
          :timer.tc(fn -> Signal.deserialize(binary, serializer: serializer) end)

        # Basic performance sanity check (should complete within reasonable time)
        assert serialize_time < 100_000
        assert deserialize_time < 100_000
      end
    end
  end

  describe "default serializer configuration" do
    test "uses JsonSerializer by default" do
      signal = %Signal{type: "test.event", source: "/test", id: "test-123"}

      # Should use JSON by default
      {:ok, binary} = Signal.serialize(signal)
      {:ok, deserialized} = Signal.deserialize(binary)

      assert deserialized.type == signal.type
      assert Jason.decode!(binary)["type"] == "test.event"
    end

    test "can override serializer per operation" do
      signal = %Signal{type: "test.event", source: "/test", id: "test-123"}

      # Use Erlang term serializer explicitly
      {:ok, term_binary} = Signal.serialize(signal, serializer: ErlangTermSerializer)
      {:ok, term_result} = Signal.deserialize(term_binary, serializer: ErlangTermSerializer)

      assert term_result.type == signal.type

      # Use MessagePack serializer explicitly
      {:ok, msgpack_binary} =
        Signal.serialize(signal, serializer: MsgpackSerializer)

      {:ok, msgpack_result} =
        Signal.deserialize(msgpack_binary, serializer: MsgpackSerializer)

      assert msgpack_result.type == signal.type

      # Different serializers should produce different binary formats
      {:ok, json_binary} = Signal.serialize(signal)
      refute term_binary == json_binary
      refute msgpack_binary == json_binary
      refute term_binary == msgpack_binary
    end
  end
end
