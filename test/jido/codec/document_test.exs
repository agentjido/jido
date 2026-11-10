defmodule Jido.Codec.DocumentTest do
  use Covenant.Case, component: "jido_action.authoring", async: true
  @moduletag obligation: "jido_action.authoring.I3"

  alias Jido.Codec.Document
  alias Jido.Codec.Document.Error

  test "accepts bounded JSON documents" do
    assert :ok = Document.check(%{"items" => [nil, true, 1, 2.5, "value"]})
  end

  test "checks exact JSON size and JSON compatibility" do
    document = %{"value" => "content"}
    size = document |> JSON.encode!() |> byte_size()

    assert :ok = Document.check_json(document, size)

    assert {:error, %Error{reason: :bytes, details: %{maximum_bytes: maximum}} = error} =
             Document.check_json(document, size - 1)

    assert maximum == size - 1
    assert Jido.Codec.Error.splode_error?(error)
    assert {:error, %Error{reason: :json}} = Document.check_json(%{"value" => self()}, size)

    assert {:error, %Error{reason: :json}} =
             Document.check_json(%{value: "atom keys change during JSON decoding"}, 100)

    assert {:error, %Error{reason: :json}} =
             Document.check_json(%{:value => "atom", "value" => "string"}, 100)
  end

  test "parses bounded JSON without losing duplicate keys or retaining the input binary" do
    value = String.duplicate("v", 128)
    json = JSON.encode!(%{"value" => value, "padding" => String.duplicate("x", 1_000_000)})

    assert {:ok, %{"value" => decoded}} = Document.decode_json(json, byte_size(json))
    assert decoded == value
    assert :binary.referenced_byte_size(decoded) == byte_size(decoded)

    assert {:error,
            %Error{
              reason: :duplicate_key,
              path: ["value"],
              details: %{key: "value"}
            }} = Document.decode_json(~s({"value":1,"value":2}), 100)
  end

  test "bounds terms without owning their value semantics" do
    assert :ok = Document.check(%{atom: self()})

    assert {:error, %Error{reason: :depth, details: %{maximum_depth: 100}}} =
             Document.check(deep_document(102))

    assert {:error, %Error{reason: :collection, details: %{maximum_size: 10_000}}} =
             Document.check(List.duplicate(nil, 10_001))

    assert {:error, %Error{reason: :list}} = Document.check([1 | :tail])

    document = List.duplicate(List.duplicate(nil, 10_000), 10)

    assert {:error, %Error{reason: :nodes, details: %{maximum_nodes: 100_000}}} =
             Document.check(document)
  end

  defp deep_document(0), do: nil
  defp deep_document(depth), do: %{"value" => deep_document(depth - 1)}
end
