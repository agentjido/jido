defmodule Jido.Signal.Serialization.ErlangTermSerializerTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Serialization.ErlangTermSerializer
  alias JidoTest.TestStructs.TestStruct

  describe "ErlangTermSerializer" do
    test "serializes and deserializes basic data types" do
      test_cases = [
        42,
        3.14159,
        "hello world",
        :atom,
        true,
        false,
        nil,
        [],
        [1, 2, 3],
        %{},
        %{"key" => "value"},
        {1, 2, 3}
      ]

      for original <- test_cases do
        {:ok, serialized} = ErlangTermSerializer.serialize(original)
        assert is_binary(serialized)
        {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)
        assert deserialized == original
      end
    end

    test "serializes and deserializes structs" do
      original = %TestStruct{field1: "test", field2: 123}
      {:ok, serialized} = ErlangTermSerializer.serialize(original)

      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)

      assert deserialized == original
    end

    test "serializes and deserializes structs with conversion" do
      original = %TestStruct{field1: "test", field2: 123}
      {:ok, serialized} = ErlangTermSerializer.serialize(original)

      # Convert map back to struct
      {:ok, deserialized} =
        ErlangTermSerializer.deserialize(serialized,
          type: "Elixir.JidoTest.TestStructs.TestStruct"
        )

      assert deserialized == original
    end

    test "serializes and deserializes nested structures" do
      original = %{
        data: %TestStruct{field1: [1, 2, 3], field2: %{nested: "value"}},
        metadata: {:version, 1},
        flags: [:enabled, :debug]
      }

      {:ok, serialized} = ErlangTermSerializer.serialize(original)
      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)

      assert deserialized == original
    end

    test "preserves atom types" do
      original = %{status: :ok, errors: [:timeout, :invalid]}
      {:ok, serialized} = ErlangTermSerializer.serialize(original)
      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)

      assert deserialized == original
      assert deserialized.status == :ok
      assert is_atom(deserialized.status)
    end

    test "preserves tuple types" do
      original = {:ok, "success", %{code: 200}}
      {:ok, serialized} = ErlangTermSerializer.serialize(original)
      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)

      assert deserialized == original
      assert is_tuple(deserialized)
      assert tuple_size(deserialized) == 3
    end

    test "handles large data efficiently" do
      large_list = Enum.to_list(1..10_000)
      {:ok, serialized} = ErlangTermSerializer.serialize(large_list)
      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)

      assert deserialized == large_list
      assert length(deserialized) == 10_000
    end

    test "handles compression" do
      # Large repetitive data should be compressed
      repetitive_data = List.duplicate("repeated string", 1000)
      {:ok, serialized} = ErlangTermSerializer.serialize(repetitive_data)

      # Should be much smaller than uncompressed
      uncompressed_size = byte_size(:erlang.term_to_binary(repetitive_data))
      compressed_size = byte_size(serialized)

      assert compressed_size < uncompressed_size
      {:ok, deserialized} = ErlangTermSerializer.deserialize(serialized)
      assert deserialized == repetitive_data
    end

    test "returns error for invalid binary" do
      invalid_binary = "not a term binary"
      {:error, _reason} = ErlangTermSerializer.deserialize(invalid_binary)
    end

    test "valid_erlang_term?/1 correctly identifies valid terms" do
      {:ok, valid_binary} = ErlangTermSerializer.serialize(%{test: "data"})
      assert ErlangTermSerializer.valid_erlang_term?(valid_binary)

      refute ErlangTermSerializer.valid_erlang_term?("invalid binary")
      refute ErlangTermSerializer.valid_erlang_term?(123)
    end
  end
end
