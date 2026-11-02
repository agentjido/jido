defmodule Jido.Authoring.PortableDocumentTest do
  use Covenant.Case, component: "jido_action.authoring", async: true

  @moduletag obligation: [
               "jido_action.authoring.I1",
               "jido_action.authoring.I2",
               "jido_action.authoring.I3"
             ]

  alias Jido.Authoring.{Document, Registry, Value}

  defmodule ExampleCodec do
    @moduledoc false

    alias Jido.Authoring.{Document, Registry, Value}

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

  test "a second document owner composes the public Registry Document and Value APIs" do
    registry =
      Registry.new!(%{
        {"atoms/example", 1} => {:atom, :example},
        {"atoms/kind", 1} => {:atom, :kind},
        {"flows/foreign", 1} => {:flow, __MODULE__}
      })

    assert {:ok, document} = ExampleCodec.encode(%{kind: :example}, registry)
    assert {:ok, %{kind: :example}} = ExampleCodec.decode(document, registry)

    assert {:ok, __MODULE__} =
             Registry.resolve(registry, {"flows/foreign", 1}, :flow)

    oversized = %{
      "type" => "wrong.owner",
      "vsn" => 99,
      "name" => List.duplicate(nil, 10_001)
    }

    assert {:error, %Document.Error{reason: :collection}} =
             ExampleCodec.decode(oversized, registry)
  end
end
