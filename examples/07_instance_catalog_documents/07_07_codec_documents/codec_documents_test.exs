Code.require_file("codec_documents.ex", __DIR__)

defmodule Jido.Examples.CodecDocumentsTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.Codec.Document
  alias Jido.Examples.CodecDocuments
  alias Jido.Examples.CodecDocuments.AddressableAgent

  test "definition and stable address remain separate portable documents" do
    ref = Ref.new!(namespace: "examples/codec", partition: "tenant-a", id: "agent-7")
    assert {:ok, definition_document} = CodecDocuments.encode_definition()
    envelope = CodecDocuments.envelope(ref, definition_document)

    assert :ok = CodecDocuments.validate_json(envelope, 64_000)
    assert {:ok, definition} = CodecDocuments.decode_definition(envelope["definition"])
    assert definition == AddressableAgent.definition()
    assert {:ok, ^ref} = Ref.from_map(envelope["address"])
  end

  test "the complete JSON byte limit is checked before storage" do
    ref = Ref.new!(namespace: "examples/codec", id: "agent-7")
    assert {:ok, definition_document} = CodecDocuments.encode_definition()
    envelope = CodecDocuments.envelope(ref, definition_document)

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
