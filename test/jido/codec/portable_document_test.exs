defmodule Jido.Codec.PortableDocumentTest do
  use Covenant.Case, component: "jido_action.authoring", async: true

  @moduletag obligation: [
               "jido_action.authoring.I1",
               "jido_action.authoring.I2",
               "jido_action.authoring.I3"
             ]

  alias Jido.Catalog
  alias Jido.Codec.{Document, Value}

  defmodule ExampleCodec do
    @moduledoc false

    alias Jido.Codec.{Document, Value}

    def encode(name, registry) do
      with {:ok, name} <- Value.encode(name, registry),
           document = %{"type" => "example.definition", "vsn" => 1, "name" => name},
           :ok <- Document.check(document) do
        {:ok, document}
      end
    end

    def decode(document, registry) do
      with :ok <- Document.check(document),
           %{"type" => "example.definition", "vsn" => 1, "name" => encoded} <- document,
           {:ok, name} <- Value.decode(encoded, registry) do
        {:ok, name}
      else
        {:error, _exception} = error -> error
        _error -> {:error, :invalid_example_document}
      end
    end
  end

  test "a second document owner composes the public Catalog, Document, and Value APIs" do
    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"atoms/example", 1} => :example,
        {"atoms/kind", 1} => :kind,
        {"flows/foreign", 1} => __MODULE__
      })

    assert {:ok, document} = ExampleCodec.encode(%{kind: :example}, registry)
    assert {:ok, %{kind: :example}} = ExampleCodec.decode(document, registry)

    assert {:ok, __MODULE__} =
             Catalog.resolve(registry, {"flows/foreign", 1})

    oversized = %{
      "type" => "wrong.owner",
      "vsn" => 99,
      "name" => List.duplicate(nil, 10_001)
    }

    assert {:error, %Document.Error{reason: :collection}} =
             ExampleCodec.decode(oversized, registry)
  end
end
