defmodule JidoTest.Agent.CodecDataTest do
  use ExUnit.Case, async: true
  alias Jido.Agent.Codec.Data

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
