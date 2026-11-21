defmodule Jido.Examples.CodecDocuments.AddressableAgent do
  @moduledoc "A definition used in the trusted codec round trip."
  use Jido.Agent, id: "examples/codec/addressable-agent", name: "codec_addressable_agent"
end

defmodule Jido.Examples.CodecDocuments do
  @moduledoc "Encodes a trusted Agent definition and its separate stable address."

  alias Jido.Agent.Address
  alias Jido.Catalog
  alias Jido.Catalog.Discovery
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
    Jido.Codec.encode(AddressableAgent.definition(), catalog: catalog())
  end

  def decode_definition(document) do
    type = if is_map(document), do: document["type"]
    vsn = if is_map(document), do: document["vsn"]

    with {:ok, codec} <- Discovery.bundled_codec(type, vsn),
         do: Jido.Codec.decode(document, catalog: catalog(), codec: codec)
  end

  def envelope(%Address{} = address, definition_document) do
    %{
      "type" => "examples.addressed-agent",
      "vsn" => 1,
      "address" => Address.to_map!(address),
      "definition" => definition_document
    }
  end

  def validate_json(document, maximum_bytes), do: Document.check_json(document, maximum_bytes)
end
