defmodule Jido.Signal.Serialization.MsgpackSerializerTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Serialization.MsgpackSerializer
  alias JidoTest.TestStructs.TestStruct

  describe "MsgpackSerializer" do
    test "serializes and deserializes basic data types" do
      test_cases = [
        42,
        3.14159,
        "hello world",
        true,
        false,
        nil,
        [],
        [1, 2, 3],
        %{},
        %{"key" => "value"}
      ]

      for original <- test_cases do
        {:ok, serialized} = MsgpackSerializer.serialize(original)
        assert is_binary(serialized)
        {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)
        assert deserialized == original
      end
    end

    test "serializes and deserializes structs" do
      original = %TestStruct{field1: "test", field2: 123}
      {:ok, serialized} = MsgpackSerializer.serialize(original)

      {:ok, deserialized} =
        MsgpackSerializer.deserialize(serialized,
          type: "Elixir.JidoTest.TestStructs.TestStruct"
        )

      assert deserialized.field1 == original.field1
      assert deserialized.field2 == original.field2
    end

    test "handles atoms by converting to strings" do
      original = %{status: :ok, type: :error}
      {:ok, serialized} = MsgpackSerializer.serialize(original)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      # Atoms should be converted to strings and back
      assert deserialized["status"] == "ok"
      assert deserialized["type"] == "error"
    end

    test "handles tuples by converting to tagged arrays" do
      original = {:ok, "success", 200}
      {:ok, serialized} = MsgpackSerializer.serialize(original)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      # Should restore as tuple but atoms become strings
      assert deserialized == {"ok", "success", 200}
      assert is_tuple(deserialized)
      assert tuple_size(deserialized) == 3
    end

    test "handles nested tuples and complex structures" do
      original = %{
        result: {:ok, "success"},
        coordinates: {1.0, 2.0, 3.0},
        nested: %{inner: {:error, "failed"}}
      }

      {:ok, serialized} = MsgpackSerializer.serialize(original)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      # Verify tuple restoration (atoms become strings)
      assert deserialized["result"] == {"ok", "success"}
      assert deserialized["coordinates"] == {1.0, 2.0, 3.0}
      assert deserialized["nested"]["inner"] == {"error", "failed"}
    end

    test "serializes and deserializes maps with mixed types" do
      original = %{
        "string_key" => "value",
        42 => "numeric_key",
        nested: %{
          data: [1, 2, 3],
          meta: true
        }
      }

      {:ok, serialized} = MsgpackSerializer.serialize(original)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      assert deserialized["string_key"] == "value"
      assert deserialized[42] == "numeric_key"
      assert deserialized["nested"]["data"] == [1, 2, 3]
      assert deserialized["nested"]["meta"] == true
    end

    test "handles empty containers" do
      test_cases = [
        %{},
        [],
        %TestStruct{field1: nil, field2: nil}
      ]

      for original <- test_cases do
        {:ok, serialized} = MsgpackSerializer.serialize(original)
        {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

        case original do
          %TestStruct{} ->
            {:ok, typed_result} =
              MsgpackSerializer.deserialize(serialized,
                type: "Elixir.JidoTest.TestStructs.TestStruct"
              )

            assert typed_result.field1 == original.field1
            assert typed_result.field2 == original.field2

          _ ->
            assert deserialized == original
        end
      end
    end

    test "preserves nil, boolean, and numeric types" do
      original = %{
        null_value: nil,
        bool_true: true,
        bool_false: false,
        integer: 42,
        float: 3.14159,
        zero: 0
      }

      {:ok, serialized} = MsgpackSerializer.serialize(original)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      assert deserialized["null_value"] == nil
      assert deserialized["bool_true"] == true
      assert deserialized["bool_false"] == false
      assert deserialized["integer"] == 42
      assert deserialized["float"] == 3.14159
      assert deserialized["zero"] == 0
    end

    test "handles large data structures" do
      large_map = 1..1000 |> Enum.into(%{}, fn i -> {i, "value_#{i}"} end)

      {:ok, serialized} = MsgpackSerializer.serialize(large_map)
      {:ok, deserialized} = MsgpackSerializer.deserialize(serialized)

      assert map_size(deserialized) == 1000
      assert deserialized[1] == "value_1"
      assert deserialized[500] == "value_500"
      assert deserialized[1000] == "value_1000"
    end

    test "returns error for invalid msgpack data" do
      invalid_binary = "not msgpack data"
      {:error, _reason} = MsgpackSerializer.deserialize(invalid_binary)
    end

    test "valid_msgpack?/1 correctly identifies valid msgpack" do
      {:ok, valid_binary} = MsgpackSerializer.serialize(%{test: "data"})
      assert MsgpackSerializer.valid_msgpack?(valid_binary)

      refute MsgpackSerializer.valid_msgpack?("invalid binary")
      refute MsgpackSerializer.valid_msgpack?(123)
    end
  end
end
