defmodule Jido.Thread.StoreTest do
  use ExUnit.Case, async: true

  alias Jido.Thread
  alias Jido.Thread.Store

  describe "Store.new/0" do
    test "creates store with InMemory adapter" do
      assert {:ok, %Store{adapter: Store.Adapters.InMemory}} = Store.new()
    end
  end

  describe "Store.save/2 and Store.load/2" do
    test "roundtrip correctly" do
      {:ok, store} = Store.new()
      thread = Thread.new(id: "t1", metadata: %{user: "alice"})

      {:ok, store} = Store.save(store, thread)
      {:ok, _store, loaded} = Store.load(store, "t1")

      assert loaded.id == "t1"
      assert loaded.metadata == %{user: "alice"}
    end
  end

  describe "Store.load/2" do
    test "returns {:error, _, :not_found} for missing thread" do
      {:ok, store} = Store.new()

      assert {:error, _store, :not_found} = Store.load(store, "nonexistent")
    end
  end

  describe "Store.append/3" do
    test "creates thread if missing and appends entries" do
      {:ok, store} = Store.new()

      entry = %{kind: :message, payload: %{role: "user", content: "Hello"}}
      {:ok, store, thread} = Store.append(store, "t2", entry)

      assert thread.id == "t2"
      assert Thread.entry_count(thread) == 1
      assert Thread.last(thread).kind == :message

      {:ok, _store, loaded} = Store.load(store, "t2")
      assert loaded.id == "t2"
      assert Thread.entry_count(loaded) == 1
    end

    test "appends to existing thread with correct seq" do
      {:ok, store} = Store.new()

      entry1 = %{kind: :message, payload: %{role: "user", content: "First"}}
      {:ok, store, _thread} = Store.append(store, "t3", entry1)

      entry2 = %{kind: :message, payload: %{role: "assistant", content: "Second"}}
      {:ok, store, thread} = Store.append(store, "t3", entry2)

      assert Thread.entry_count(thread) == 2
      assert Thread.last(thread).seq == 1
      assert Thread.get_entry(thread, 0).payload.content == "First"
      assert Thread.get_entry(thread, 1).payload.content == "Second"

      {:ok, _store, loaded} = Store.load(store, "t3")
      assert Thread.entry_count(loaded) == 2
    end
  end

  describe "Store.delete/2" do
    test "removes thread" do
      {:ok, store} = Store.new()
      thread = Thread.new(id: "t4")

      {:ok, store} = Store.save(store, thread)
      {:ok, store, _loaded} = Store.load(store, "t4")

      {:ok, store} = Store.delete(store, "t4")
      assert {:error, _store, :not_found} = Store.load(store, "t4")
    end
  end

  describe "Store.list/1" do
    test "returns all thread IDs" do
      {:ok, store} = Store.new()

      {:ok, store, ids} = Store.list(store)
      assert ids == []

      {:ok, store} = Store.save(store, Thread.new(id: "t5"))
      {:ok, store} = Store.save(store, Thread.new(id: "t6"))
      {:ok, store} = Store.save(store, Thread.new(id: "t7"))

      {:ok, _store, ids} = Store.list(store)
      assert Enum.sort(ids) == ["t5", "t6", "t7"]
    end
  end
end
