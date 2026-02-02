defmodule Jido.Thread.Store.Adapters.JournalBackedTest do
  use ExUnit.Case, async: true

  alias Jido.Thread
  alias Jido.Thread.Store
  alias Jido.Thread.Store.Adapters.JournalBacked
  alias Jido.Thread.Entry

  describe "init/1" do
    test "initializes with Journal and default InMemory adapter" do
      assert {:ok, state} = JournalBacked.init([])
      assert %{journal: journal} = state
      assert journal.adapter == Jido.Signal.Journal.Adapters.InMemory
    end

    test "accepts custom journal adapter" do
      assert {:ok, state} = JournalBacked.init(journal_adapter: Jido.Signal.Journal.Adapters.ETS)
      assert %{journal: journal} = state
      assert journal.adapter == Jido.Signal.Journal.Adapters.ETS
    end
  end

  describe "save/2 and load/2 roundtrip" do
    test "preserves entries in correct seq order" do
      {:ok, store} = Store.new(JournalBacked)

      thread =
        Thread.new(id: "t1")
        |> Thread.append(%{kind: :message, payload: %{role: "user", content: "First"}})
        |> Thread.append(%{kind: :message, payload: %{role: "assistant", content: "Second"}})
        |> Thread.append(%{kind: :tool_call, payload: %{name: "search", args: %{}}})

      {:ok, store} = Store.save(store, thread)
      {:ok, _store, loaded} = Store.load(store, "t1")

      assert loaded.id == "t1"
      assert Thread.entry_count(loaded) == 3

      entries = Thread.to_list(loaded)
      assert Enum.at(entries, 0).seq == 0
      assert Enum.at(entries, 1).seq == 1
      assert Enum.at(entries, 2).seq == 2
      assert Enum.at(entries, 0).payload.content == "First"
      assert Enum.at(entries, 1).payload.content == "Second"
      assert Enum.at(entries, 2).payload.name == "search"
    end

    test "preserves entry metadata" do
      {:ok, store} = Store.new(JournalBacked)

      thread =
        Thread.new(id: "meta-test")
        |> Thread.append(%{
          kind: :message,
          payload: %{role: "user", content: "Hello"},
          refs: %{signal_id: "sig_123", agent_id: "agent_456"}
        })

      {:ok, store} = Store.save(store, thread)
      {:ok, _store, loaded} = Store.load(store, "meta-test")

      entry = Thread.last(loaded)
      assert entry.refs == %{signal_id: "sig_123", agent_id: "agent_456"}
    end
  end

  describe "load/2" do
    test "returns :not_found for missing thread" do
      {:ok, store} = Store.new(JournalBacked)

      assert {:error, _store, :not_found} = Store.load(store, "nonexistent")
    end
  end

  describe "append/3" do
    test "creates thread if missing" do
      {:ok, store} = Store.new(JournalBacked)

      entry = %{kind: :message, payload: %{role: "user", content: "Hello"}}
      {:ok, store, thread} = Store.append(store, "new-thread", entry)

      assert thread.id == "new-thread"
      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).kind == :message

      {:ok, _store, loaded} = Store.load(store, "new-thread")
      assert Thread.entry_count(loaded) == 1
    end

    test "appends to existing thread with correct seq" do
      {:ok, store} = Store.new(JournalBacked)

      entry1 = %{kind: :message, payload: %{role: "user", content: "First"}}
      {:ok, store, _thread} = Store.append(store, "t2", entry1)

      entry2 = %{kind: :message, payload: %{role: "assistant", content: "Second"}}
      {:ok, store, thread} = Store.append(store, "t2", entry2)

      assert Thread.entry_count(thread) == 2
      assert Thread.get_entry(thread, 0).seq == 0
      assert Thread.get_entry(thread, 1).seq == 1
      assert Thread.get_entry(thread, 0).payload.content == "First"
      assert Thread.get_entry(thread, 1).payload.content == "Second"

      {:ok, _store, loaded} = Store.load(store, "t2")
      assert Thread.entry_count(loaded) == 2
    end

    test "handles multiple entries in single append" do
      {:ok, store} = Store.new(JournalBacked)

      entries = [
        %{kind: :message, payload: %{role: "user", content: "One"}},
        %{kind: :message, payload: %{role: "assistant", content: "Two"}},
        %{kind: :message, payload: %{role: "user", content: "Three"}}
      ]

      {:ok, _store, thread} = Store.append(store, "batch", entries)

      assert Thread.entry_count(thread) == 3
      assert Thread.get_entry(thread, 0).payload.content == "One"
      assert Thread.get_entry(thread, 1).payload.content == "Two"
      assert Thread.get_entry(thread, 2).payload.content == "Three"
    end
  end

  describe "entry kinds" do
    test "survive encoding/decoding as atoms" do
      {:ok, store} = Store.new(JournalBacked)

      kinds = [
        :message,
        :tool_call,
        :tool_result,
        :signal_in,
        :signal_out,
        :note,
        :error,
        :checkpoint
      ]

      thread =
        Enum.reduce(kinds, Thread.new(id: "kinds-test"), fn kind, t ->
          Thread.append(t, %{kind: kind, payload: %{test: true}})
        end)

      {:ok, store} = Store.save(store, thread)
      {:ok, _store, loaded} = Store.load(store, "kinds-test")

      loaded_kinds = loaded |> Thread.to_list() |> Enum.map(& &1.kind)
      assert loaded_kinds == kinds
    end
  end

  describe "multiple threads" do
    test "stores and retrieves multiple threads independently" do
      {:ok, store} = Store.new(JournalBacked)

      {:ok, store, _} =
        Store.append(store, "thread-a", %{kind: :message, payload: %{content: "A"}})

      {:ok, store, _} =
        Store.append(store, "thread-b", %{kind: :message, payload: %{content: "B"}})

      {:ok, store, _} =
        Store.append(store, "thread-a", %{kind: :message, payload: %{content: "A2"}})

      {:ok, store, thread_a} = Store.load(store, "thread-a")
      {:ok, _store, thread_b} = Store.load(store, "thread-b")

      assert Thread.entry_count(thread_a) == 2
      assert Thread.entry_count(thread_b) == 1
      assert Thread.last(thread_a).payload.content == "A2"
      assert Thread.last(thread_b).payload.content == "B"
    end
  end

  describe "Entry struct handling" do
    test "handles Entry structs directly" do
      {:ok, store} = Store.new(JournalBacked)

      entry = Entry.new(kind: :message, payload: %{role: "user", content: "Test"})
      {:ok, _store, thread} = Store.append(store, "entry-struct", [entry])

      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).kind == :message
    end
  end
end
