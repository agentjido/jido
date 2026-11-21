defmodule Jido.Codec.ValueTest do
  use Covenant.Case, component: "jido_action.authoring", async: true
  @moduletag obligation: "jido_action.authoring.I2"

  alias Jido.Catalog
  alias Jido.Catalog.Error, as: CatalogError
  alias Jido.Codec.Value
  alias Jido.Codec.Value.Error

  test "round trips portable values and registered atoms" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"atoms/count", 1} => :count,
        {"atoms/ready", 1} => :ready
      })

    value = %{"status" => :ready, 3 => [true, nil], count: 2}

    assert {:ok, encoded} = Value.encode(value, registry)
    assert {:ok, ^value} = Value.decode(encoded, registry)
  end

  test "rejects unregistered atoms and nonportable values" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})

    assert {:error, %CatalogError{}} = Value.encode(:missing, registry)
    assert {:error, %Error{} = error} = Value.encode(self(), registry)
    assert Jido.Codec.Error.splode_error?(error)
    assert {:error, %Error{}} = Value.encode({:tuple}, registry)
  end

  test "keeps the full path for an unregistered nested atom" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})

    assert {:error, %CatalogError{details: %{path: ["outer", 0]}}} =
             Value.encode(%{"outer" => [:missing]}, registry)
  end

  test "sorts map entries by the encoded key" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"atoms/z-write-a", 1} => :a,
        {"atoms/a-write-z", 1} => :z
      })

    assert {:ok, %{"entries" => entries}} = Value.encode(%{a: 1, z: 2}, registry)

    assert Enum.map(entries, &get_in(&1, ["key", "id"])) == [
             "atoms/a-write-z",
             "atoms/z-write-a"
           ]
  end

  test "round trips Boolean map keys in deterministic order" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})
    value = %{true => "yes", false => "no"}

    assert {:ok, %{"entries" => entries} = encoded} = Value.encode(value, registry)
    assert Enum.map(entries, & &1["key"]) == [false, true]
    assert {:ok, ^value} = Value.decode(encoded, registry)
  end

  test "rejects unsupported map keys before it sorts portable keys" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})

    assert {:error, %Error{reason: :map_key, path: []}} =
             Value.encode(%{{:unsupported, :key} => self()}, registry)
  end

  test "portable atom decoding validates the resolved value" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{{"atoms/invalid", 1} => "not-an-atom"})

    assert {:error, %Error{reason: :atom}} =
             Value.decode(%{"$type" => "atom", "id" => "atoms/invalid", "vsn" => 1}, registry)
  end

  test "decode rejects invalid UTF-8 strings at every value position" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})
    invalid = <<255>>

    for encoded <- [
          invalid,
          [invalid],
          %{"$type" => "map", "entries" => [%{"key" => invalid, "value" => 1}]},
          %{"$type" => "map", "entries" => [%{"key" => "key", "value" => invalid}]}
        ] do
      assert {:error, %Error{reason: :string}} = Value.decode(encoded, registry)
    end
  end

  test "decode rejects a plain map that would become a struct" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"atoms/struct", 1} => :__struct__,
        {"atoms/uri", 1} => URI
      })

    encoded = %{
      "$type" => "map",
      "entries" => [
        %{
          "key" => %{"$type" => "atom", "id" => "atoms/struct", "vsn" => 1},
          "value" => %{"$type" => "atom", "id" => "atoms/uri", "vsn" => 1}
        }
      ]
    }

    assert {:error, %Error{reason: :value}} = Value.decode(encoded, registry)
  end

  test "decode returns structured errors for improper lists" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})
    encoded_map = %{"$type" => "map", "entries" => [%{"key" => "key", "value" => 1} | :tail]}

    assert {:error, %Error{reason: :list, path: []}} = Value.decode([1 | :tail], registry)

    assert {:error, %Error{reason: :list, path: ["entries"]}} =
             Value.decode(encoded_map, registry)
  end

  test "enforces depth before recursive encode and decode" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})
    nested = Enum.reduce(1..101, 0, fn _index, value -> [value] end)

    assert {:error, %Error{reason: :depth, details: %{maximum_depth: 100}}} =
             Value.encode(nested, registry)

    assert {:error, %Error{reason: :depth, details: %{maximum_depth: 100}}} =
             Value.decode(nested, registry)
  end

  test "enforces collection size before recursive encode and decode" do
    registry = Catalog.from_targets!(__MODULE__, :jido, %{})
    values = List.duplicate(0, 10_001)

    assert {:error, %Error{reason: :collection, details: %{maximum_size: 10_000}}} =
             Value.encode(values, registry)

    assert {:error, %Error{reason: :collection, details: %{maximum_size: 10_000}}} =
             Value.decode(values, registry)
  end

  test "every decoded portable value can be encoded again" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{{"atoms/ready", 1} => :ready})

    for encoded <- [
          nil,
          true,
          1,
          2.5,
          "value",
          [1, %{"$type" => "atom", "id" => "atoms/ready", "vsn" => 1}],
          %{
            "$type" => "map",
            "entries" => [
              %{
                "key" => "status",
                "value" => %{"$type" => "atom", "id" => "atoms/ready", "vsn" => 1}
              }
            ]
          }
        ] do
      assert {:ok, value} = Value.decode(encoded, registry)
      assert {:ok, _encoded_again} = Value.encode(value, registry)
    end
  end
end
