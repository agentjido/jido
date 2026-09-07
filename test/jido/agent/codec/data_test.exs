defmodule Jido.Agent.Codec.DataTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Codec.{Data, Registry}

  test "encode and decode preserve portable data and trusted references" do
    uri = %URI{scheme: "https", host: "example.com"}

    registry =
      Registry.new!(%{
        "atoms/nested" => {:atom, :nested},
        "atoms/ok" => {:atom, :ok},
        "atoms/raw" => {:atom, :raw},
        "atoms/status" => {:atom, :status},
        "values/uri" => {:value, uri}
      })

    value = %{status: :ok, nested: {uri, [true, nil, 3.5]}, raw: <<255, 0>>}

    assert {:ok, encoded} = Data.encode(value, registry)
    assert encoded["$type"] == "map"
    assert {:ok, ^value} = Data.decode(encoded, registry)
    assert {:ok, %{"$type" => "binary", "value" => base64}} = Data.encode(<<255>>, registry)
    assert Base.decode64!(base64) == <<255>>
  end

  test "encode rejects missing references, runtime values, improper lists, and excess depth" do
    registry = Registry.new!(%{})

    for value <- [:missing, %URI{}, self(), [1 | :tail]] do
      assert {:error, %Jido.Error.ValidationError{}} = Data.encode(value, registry)
    end

    assert {:error, %Jido.Error.ValidationError{message: "Authoring data is too deep"}} =
             Data.encode(:value, registry, 101)
  end

  test "decode rejects malformed tags, references, map entries, and base64" do
    registry = Registry.new!(%{"atoms/ok" => {:atom, :ok}})
    assert {:ok, :ok} = Data.decode(%{"$type" => "atom", "id" => "atoms/ok"}, registry)

    for value <- [
          %{"$type" => "atom", "id" => "missing"},
          %{"$type" => "binary", "value" => "not-base64!"},
          %{"$type" => "tuple", "items" => :invalid},
          %{"$type" => "map", "entries" => [:invalid]},
          %{"$type" => "unknown"}
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = Data.decode(value, registry)
    end

    duplicate = %{
      "$type" => "map",
      "entries" => [["same", 1], ["same", 2]]
    }

    assert {:error, %Jido.Error.ValidationError{message: "Duplicate decoded map key"}} =
             Data.decode(duplicate, registry)
  end

  test "map traversal keeps the map, depth, node, string, and list bounds" do
    map = Map.new(1..10_000, &{"key-#{&1}", &1})
    assert check_document(map) == :ok

    assert check_document(Map.put(map, "extra", 0)) ==
             expected_error("Invalid or oversized JSON document value")

    nested = Enum.reduce(1..100, 0, fn _, child -> %{"a" => child} end)
    assert check_document(nested) == :ok

    assert check_document(%{"a" => nested}) ==
             expected_error("Authoring document exceeds its size or depth limit")

    near_limit = List.duplicate(List.duplicate(0, 10_000), 9)
    assert check_document(near_limit ++ [List.duplicate(0, 9_989)]) == :ok

    assert check_document(near_limit ++ [List.duplicate(0, 9_990)]) ==
             expected_error("Authoring document exceeds its node limit")

    assert check_document(near_limit ++ [List.duplicate(0, 9_991)]) ==
             expected_error("Authoring document exceeds its size or depth limit")

    assert check_document(%{"a" => List.duplicate(0, 10_001)}) ==
             expected_error("Invalid or oversized document list")

    assert check_document(%{"a" => [0 | :tail]}) ==
             expected_error("Invalid or oversized document list")
  end

  test "all map keys are checked before values and map entry error order stays stable" do
    assert check_document(%{:bad => nil, "value" => self()}) ==
             expected_error("Document object keys must be strings")

    for base <- [%{"a" => nil, "b" => nil}, Map.new(1..64, &{"key-#{&1}", nil})] do
      [first, second | _] = Enum.map(base, &elem(&1, 0))
      invalid = base |> Map.put(first, <<255>>) |> Map.put(second, self())

      assert check_document(invalid) == expected_error("Document strings must be UTF-8")

      assert check_document(Map.put(invalid, first, nil)) ==
               expected_error("Invalid or oversized JSON document value")
    end

    assert check_document(%{<<255>> => self()}) ==
             expected_error("Document strings must be UTF-8")

    assert check_document(%{String.duplicate("a", 1_048_577) => nil}) ==
             expected_error("Invalid or oversized JSON document value")
  end

  defp check_document(value) do
    case Data.check_document(value) do
      :ok -> :ok
      {:error, error} -> {:error, error |> Map.from_struct() |> Map.delete(:stacktrace)}
    end
  end

  defp expected_error(message) do
    {:error, error} = Jido.Agent.Authoring.error(message)
    {:error, error |> Map.from_struct() |> Map.delete(:stacktrace)}
  end
end
