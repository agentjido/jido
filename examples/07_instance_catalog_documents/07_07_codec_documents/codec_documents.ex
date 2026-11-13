defmodule Jido.Examples.CodecDocuments.AddressableAgent do
  @moduledoc "A definition used in the trusted codec round trip."
  use Jido.Agent, id: "examples/codec/addressable-agent", name: "codec_addressable_agent"
end

defmodule Jido.Examples.CodecDocuments do
  @moduledoc "Encodes a trusted Agent definition and its separate stable address."

  alias Jido.Agent.Ref
  alias Jido.Catalog
  alias Jido.Codec.Document
  alias Jido.Examples.CodecDocuments.AddressableAgent

  def catalog do
    manifest =
      Jido.Catalog.Manifest.new!(
        AddressableAgent,
        :jido,
        AddressableAgent.__jido_catalog_manifest__()
      )

    Catalog.new!([manifest])
  end

  def encode_definition do
    Jido.Codec.encode(AddressableAgent.definition(),
      catalog: catalog(),
      codec: Jido.Agent.Codec
    )
  end

  def decode_definition(document) do
    Jido.Codec.decode(document, catalog: catalog(), codec: Jido.Agent.Codec)
  end

  def envelope(%Ref{} = ref, definition_document) do
    %{
      "type" => "examples.addressed-agent",
      "vsn" => 1,
      "address" => Ref.to_map!(ref),
      "definition" => definition_document
    }
  end

  def validate_json(document, maximum_bytes), do: Document.check_json(document, maximum_bytes)
end
