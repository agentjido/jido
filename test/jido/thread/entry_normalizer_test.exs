defmodule JidoTest.Thread.EntryNormalizerTest do
  use ExUnit.Case, async: true

  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer

  describe "normalize/4" do
    test "applies consistent defaults for Entry structs" do
      entry = %Entry{id: nil, seq: 10, at: nil, kind: nil, payload: nil, refs: nil}

      normalized = EntryNormalizer.normalize(entry, 3, 1_234)

      assert normalized.seq == 3
      assert normalized.at == 1_234
      assert normalized.kind == :note
      assert normalized.payload == %{}
      assert normalized.refs == %{}
      assert is_binary(normalized.id)
    end

    test "accepts atom and string keys for map input" do
      input = %{
        "id" => "entry_123",
        "at" => 999,
        "kind" => :message,
        "payload" => %{"text" => "hello"},
        "refs" => %{"source" => "test"}
      }

      normalized = EntryNormalizer.normalize(input, 4, 1_234)

      assert normalized.id == "entry_123"
      assert normalized.seq == 4
      assert normalized.at == 999
      assert normalized.kind == :message
      assert normalized.payload == %{"text" => "hello"}
      assert normalized.refs == %{"source" => "test"}
    end
  end

  describe "normalize_many/4" do
    test "assigns monotonic sequence values from base_seq" do
      entries = [%{kind: :message}, %{kind: :message}, %{kind: :message}]

      normalized = EntryNormalizer.normalize_many(entries, 7, 1_000)

      assert Enum.map(normalized, & &1.seq) == [7, 8, 9]
    end

    test "batch normalization calls the ID generator in order only for missing IDs" do
      generator = fn ->
        count = Process.get(:generated_entry_count, 0) + 1
        Process.put(:generated_entry_count, count)
        "generated_#{count}"
      end

      entries = [
        %{"id" => "kept"},
        %Entry{id: nil, seq: 99, at: 2, kind: :note},
        %{},
        %{id: "last"}
      ]

      normalized = EntryNormalizer.normalize_many(entries, 5, 1_000, id_generator: generator)

      assert Enum.map(normalized, &{&1.id, &1.seq, &1.at}) ==
               [
                 {"kept", 5, 1_000},
                 {"generated_1", 6, 2},
                 {"generated_2", 7, 1_000},
                 {"last", 8, 1_000}
               ]

      assert Process.get(:generated_entry_count) == 2
      assert EntryNormalizer.normalize_many([], 9, 1_000, id_generator: generator) == []
      assert Process.get(:generated_entry_count) == 2
    end

    test "supports custom id generation" do
      normalized =
        EntryNormalizer.normalize(%{kind: :note}, 0, 100, id_generator: fn -> "custom_id" end)

      assert normalized.id == "custom_id"
    end
  end
end
