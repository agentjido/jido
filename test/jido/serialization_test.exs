defmodule Jido.SerializationTest do
  use ExUnit.Case

  alias Jido.Serialization.{JsonSerializer, JsonDecoder, ModuleNameTypeProvider}
  alias JidoTest.TestStructs.{TestStruct, CustomDecodedStruct}

  describe "JsonSerializer" do
    test "serializes and deserializes structs" do
      original = %TestStruct{field1: "test", field2: 123}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized, type: "Elixir.JidoTest.TestStructs.TestStruct")

      assert deserialized == original
    end

    test "serializes and deserializes structs with nil values" do
      original = %TestStruct{field1: nil, field2: nil}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized, type: "Elixir.JidoTest.TestStructs.TestStruct")

      assert deserialized == original
    end

    test "serializes and deserializes structs with nested maps" do
      original = %TestStruct{field1: %{nested: "value"}, field2: 123}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized, type: "Elixir.JidoTest.TestStructs.TestStruct")

      assert deserialized == original
    end

    test "serializes and deserializes structs with lists" do
      original = %TestStruct{field1: [1, 2, 3], field2: ["a", "b", "c"]}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized, type: "Elixir.JidoTest.TestStructs.TestStruct")

      assert deserialized == original
    end

    test "serializes and deserializes maps" do
      original = %{"key" => "value", "nested" => %{"num" => 42}}
      serialized = JsonSerializer.serialize(original)
      deserialized = JsonSerializer.deserialize(serialized)

      assert deserialized == original
    end

    test "serializes and deserializes empty maps" do
      original = %{}
      serialized = JsonSerializer.serialize(original)
      deserialized = JsonSerializer.deserialize(serialized)

      assert deserialized == original
    end

    test "serializes and deserializes maps with lists" do
      original = %{"list" => [1, 2, %{"nested" => "value"}]}
      serialized = JsonSerializer.serialize(original)
      deserialized = JsonSerializer.deserialize(serialized)

      assert deserialized == original
    end

    test "handles custom JsonDecoder implementation" do
      original = %CustomDecodedStruct{value: 5}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized,
          type: "Elixir.JidoTest.TestStructs.CustomDecodedStruct"
        )

      # Value doubled by custom decoder
      assert deserialized.value == 10
    end

    test "handles custom JsonDecoder with nil value" do
      original = %CustomDecodedStruct{value: nil}
      serialized = JsonSerializer.serialize(original)

      deserialized =
        JsonSerializer.deserialize(serialized,
          type: "Elixir.JidoTest.TestStructs.CustomDecodedStruct"
        )

      assert deserialized.value == nil
    end

    test "raises on invalid JSON" do
      assert_raise Jason.DecodeError, fn ->
        JsonSerializer.deserialize("{invalid_json",
          type: "Elixir.JidoTest.TestStructs.TestStruct"
        )
      end
    end

    test "raises on non-existent type" do
      assert_raise ArgumentError, fn ->
        JsonSerializer.deserialize("{}", type: "NonExistentModule")
      end
    end
  end

  describe "ModuleNameTypeProvider" do
    test "converts struct to type string" do
      struct = %TestStruct{}
      type_string = ModuleNameTypeProvider.to_string(struct)

      assert type_string == "Elixir.JidoTest.TestStructs.TestStruct"
    end

    test "converts type string to struct" do
      type_string = "Elixir.JidoTest.TestStructs.TestStruct"
      struct = ModuleNameTypeProvider.to_struct(type_string)

      assert struct == %TestStruct{}
    end

    test "handles nested module names" do
      type_string = ModuleNameTypeProvider.to_string(%CustomDecodedStruct{})
      assert type_string == "Elixir.JidoTest.TestStructs.CustomDecodedStruct"
    end

    test "raises on invalid module name format" do
      assert_raise ArgumentError, fn ->
        ModuleNameTypeProvider.to_struct("InvalidModuleName")
      end
    end

    test "raises on non-existent module" do
      assert_raise ArgumentError, fn ->
        ModuleNameTypeProvider.to_struct("Elixir.NonExistent.Module")
      end
    end
  end

  describe "JsonDecoder" do
    test "default implementation returns data unchanged" do
      data = %{some: "data"}
      assert JsonDecoder.decode(data) == data
    end

    test "custom implementation modifies data" do
      data = %CustomDecodedStruct{value: 5}
      decoded = JsonDecoder.decode(data)

      assert decoded.value == 10
    end

    test "default implementation handles various data types" do
      assert JsonDecoder.decode(nil) == nil
      assert JsonDecoder.decode([1, 2, 3]) == [1, 2, 3]
      assert JsonDecoder.decode("string") == "string"
      assert JsonDecoder.decode(123) == 123
    end
  end
end
