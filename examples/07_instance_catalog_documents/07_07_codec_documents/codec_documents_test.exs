Code.require_file("codec_documents.ex", __DIR__)

defmodule Jido.Examples.CodecDocumentsTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Agent.Address
  alias Jido.Codec.{Document, Issue}
  alias Jido.Examples.CodecDocuments
  alias Jido.Examples.CodecDocuments.AddressableAgent

  setup do
    publication = :persistent_term.get({:jido, :catalog}, :not_ready)
    :persistent_term.erase({:jido, :catalog})

    on_exit(fn ->
      if publication == :not_ready,
        do: :persistent_term.erase({:jido, :catalog}),
        else: :persistent_term.put({:jido, :catalog}, publication)
    end)

    :ok
  end

  test "definition and stable address remain separate offline documents" do
    address = Address.new!(namespace: "examples/codec", partition: "tenant-a", id: "agent-7")
    assert {:ok, definition_document} = CodecDocuments.encode_definition()
    envelope = CodecDocuments.envelope(address, definition_document)

    assert :ok = CodecDocuments.validate_json(envelope, 64_000)
    assert {:ok, definition} = CodecDocuments.decode_definition(envelope["definition"])
    assert definition == AddressableAgent.definition()
    assert {:ok, ^address} = Address.from_map(envelope["address"])
  end

  test "unknown bundled types and versions fail before decode" do
    assert {:ok, definition_document} = CodecDocuments.encode_definition()

    assert {:error, [%Issue{code: :unsupported_document, path: ["type"]}]} =
             definition_document
             |> Map.put("type", "unknown.agent.definition")
             |> CodecDocuments.decode_definition()

    assert {:error,
            [
              %Issue{
                code: :unsupported_document,
                path: ["vsn"],
                details: %{supported_vsns: [1]}
              }
            ]} =
             definition_document
             |> Map.put("vsn", 2)
             |> CodecDocuments.decode_definition()
  end

  test "the complete JSON byte limit is checked before storage" do
    address = Address.new!(namespace: "examples/codec", id: "agent-7")
    assert {:ok, definition_document} = CodecDocuments.encode_definition()
    envelope = CodecDocuments.envelope(address, definition_document)

    assert {:error, %Document.Error{reason: :bytes}} =
             CodecDocuments.validate_json(envelope, 32)
  end

  test "duplicate JSON keys and excessive nesting are rejected" do
    assert {:error, %Document.Error{reason: :duplicate_key}} =
             Document.decode_json(~s({"type":"a","type":"b"}), 1_000)

    too_deep = Enum.reduce(1..102, "leaf", fn _index, value -> [value] end)
    assert {:error, %Document.Error{reason: :depth}} = Document.check(too_deep)
  end
end
