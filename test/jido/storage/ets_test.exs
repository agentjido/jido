defmodule JidoTest.Storage.ETSTest do
  use ExUnit.Case, async: true

  alias Jido.Storage
  alias Jido.Storage.ETS
  alias Jido.Thread
  alias Jido.Thread.Entry

  defp unique_table(test_name) do
    :"test_storage_#{test_name}_#{System.unique_integer([:positive])}"
  end

  describe "normalize_storage/1" do
    test "module atom normalizes to {Module, []}" do
      assert {Jido.Storage.ETS, []} = Storage.normalize_storage(Jido.Storage.ETS)
    end

    test "tuple passes through unchanged" do
      assert {Jido.Storage.ETS, [table: :custom]} =
               Storage.normalize_storage({Jido.Storage.ETS, table: :custom})
    end
  end

  describe "checkpoint operations" do
    test "get_checkpoint/2 returns :not_found for missing key" do
      opts = [table: unique_table(:get_missing)]

      assert :not_found = ETS.get_checkpoint(:nonexistent_key, opts)
    end

    test "put_checkpoint/3 stores and get_checkpoint/2 retrieves data" do
      opts = [table: unique_table(:put_get)]

      assert :ok = ETS.put_checkpoint(:my_key, %{state: "saved"}, opts)
      assert {:ok, %{state: "saved"}} = ETS.get_checkpoint(:my_key, opts)
    end

    test "put_checkpoint/3 overwrites existing data" do
      opts = [table: unique_table(:overwrite)]

      assert :ok = ETS.put_checkpoint(:key, %{version: 1}, opts)
      assert {:ok, %{version: 1}} = ETS.get_checkpoint(:key, opts)

      assert :ok = ETS.put_checkpoint(:key, %{version: 2}, opts)
      assert {:ok, %{version: 2}} = ETS.get_checkpoint(:key, opts)
    end

    test "delete_checkpoint/2 removes data" do
      opts = [table: unique_table(:delete)]

      assert :ok = ETS.put_checkpoint(:to_delete, %{data: "exists"}, opts)
      assert {:ok, _} = ETS.get_checkpoint(:to_delete, opts)

      assert :ok = ETS.delete_checkpoint(:to_delete, opts)
      assert :not_found = ETS.get_checkpoint(:to_delete, opts)
    end

    test "delete_checkpoint/2 succeeds even if key doesn't exist" do
      opts = [table: unique_table(:delete_missing)]

      assert :ok = ETS.delete_checkpoint(:never_existed, opts)
    end

    test "supports various key types" do
      opts = [table: unique_table(:key_types)]

      assert :ok = ETS.put_checkpoint("string_key", :data1, opts)
      assert :ok = ETS.put_checkpoint({:tuple, :key}, :data2, opts)
      assert :ok = ETS.put_checkpoint(123, :data3, opts)

      assert {:ok, :data1} = ETS.get_checkpoint("string_key", opts)
      assert {:ok, :data2} = ETS.get_checkpoint({:tuple, :key}, opts)
      assert {:ok, :data3} = ETS.get_checkpoint(123, opts)
    end
  end

  describe "thread operations" do
    test "load_thread/2 returns :not_found for missing thread" do
      opts = [table: unique_table(:load_missing)]

      assert :not_found = ETS.load_thread("nonexistent_thread", opts)
    end

    test "append_thread/3 creates thread with entries" do
      opts = [table: unique_table(:create_thread)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entries = [
        %{kind: :message, payload: %{role: "user", content: "Hello"}}
      ]

      assert {:ok, %Thread{} = thread} = ETS.append_thread(thread_id, entries, opts)
      assert thread.id == thread_id
      assert thread.rev == 1
      assert length(thread.entries) == 1
      assert hd(thread.entries).kind == :message
    end

    test "append_thread/3 appends to existing thread" do
      opts = [table: unique_table(:append_thread)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entry1 = %{kind: :message, payload: %{content: "First"}}
      entry2 = %{kind: :message, payload: %{content: "Second"}}

      {:ok, thread1} = ETS.append_thread(thread_id, [entry1], opts)
      assert thread1.rev == 1
      assert length(thread1.entries) == 1

      {:ok, thread2} = ETS.append_thread(thread_id, [entry2], opts)
      assert thread2.rev == 2
      assert length(thread2.entries) == 2
      assert Enum.at(thread2.entries, 0).payload.content == "First"
      assert Enum.at(thread2.entries, 1).payload.content == "Second"
    end

    test "append_thread/3 with expected_rev: succeeds when rev matches" do
      opts = [table: unique_table(:expected_rev_match)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      {:ok, thread1} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert thread1.rev == 1

      {:ok, thread2} =
        ETS.append_thread(thread_id, [%{kind: :note}], Keyword.put(opts, :expected_rev, 1))

      assert thread2.rev == 2
    end

    test "append_thread/3 with expected_rev: returns {:error, :conflict} when rev doesn't match" do
      opts = [table: unique_table(:expected_rev_conflict)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      {:ok, _} = ETS.append_thread(thread_id, [%{kind: :note}], opts)

      assert {:error, :conflict} =
               ETS.append_thread(thread_id, [%{kind: :note}], Keyword.put(opts, :expected_rev, 0))

      assert {:error, :conflict} =
               ETS.append_thread(thread_id, [%{kind: :note}], Keyword.put(opts, :expected_rev, 5))
    end

    test "load_thread/2 returns correct %Jido.Thread{} with all entries" do
      opts = [table: unique_table(:load_thread)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entries = [
        %{kind: :message, payload: %{role: "user", content: "Hello"}},
        %{kind: :message, payload: %{role: "assistant", content: "Hi there"}},
        %{kind: :tool_call, payload: %{name: "search", args: %{}}}
      ]

      {:ok, _} = ETS.append_thread(thread_id, entries, opts)

      assert {:ok, %Thread{} = thread} = ETS.load_thread(thread_id, opts)
      assert thread.id == thread_id
      assert thread.rev == 3
      assert length(thread.entries) == 3

      assert Enum.all?(thread.entries, fn e -> %Entry{} = e end)

      [e0, e1, e2] = thread.entries
      assert e0.kind == :message
      assert e1.kind == :message
      assert e2.kind == :tool_call
    end

    test "delete_thread/2 removes thread and all entries" do
      opts = [table: unique_table(:delete_thread)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entries = [
        %{kind: :message, payload: %{content: "Entry 1"}},
        %{kind: :message, payload: %{content: "Entry 2"}}
      ]

      {:ok, _} = ETS.append_thread(thread_id, entries, opts)
      assert {:ok, _} = ETS.load_thread(thread_id, opts)

      assert :ok = ETS.delete_thread(thread_id, opts)
      assert :not_found = ETS.load_thread(thread_id, opts)
    end

    test "delete_thread/2 succeeds even if thread doesn't exist" do
      opts = [table: unique_table(:delete_missing_thread)]

      assert :ok = ETS.delete_thread("never_existed_thread", opts)
    end

    test "thread entries have correct seq numbers assigned" do
      opts = [table: unique_table(:seq_numbers)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entries = [
        %{kind: :note, payload: %{text: "First"}},
        %{kind: :note, payload: %{text: "Second"}},
        %{kind: :note, payload: %{text: "Third"}}
      ]

      {:ok, thread} = ETS.append_thread(thread_id, entries, opts)

      assert Enum.at(thread.entries, 0).seq == 0
      assert Enum.at(thread.entries, 1).seq == 1
      assert Enum.at(thread.entries, 2).seq == 2

      more_entries = [
        %{kind: :note, payload: %{text: "Fourth"}}
      ]

      {:ok, updated_thread} = ETS.append_thread(thread_id, more_entries, opts)

      assert Enum.at(updated_thread.entries, 3).seq == 3
    end

    test "thread rev increments correctly" do
      opts = [table: unique_table(:rev_increment)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      {:ok, t1} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert t1.rev == 1

      {:ok, t2} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert t2.rev == 2

      {:ok, t3} = ETS.append_thread(thread_id, [%{kind: :note}, %{kind: :note}], opts)
      assert t3.rev == 4

      {:ok, loaded} = ETS.load_thread(thread_id, opts)
      assert loaded.rev == 4
    end

    test "entries get unique IDs assigned" do
      opts = [table: unique_table(:entry_ids)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entries = [
        %{kind: :message, payload: %{content: "One"}},
        %{kind: :message, payload: %{content: "Two"}}
      ]

      {:ok, thread} = ETS.append_thread(thread_id, entries, opts)

      [e1, e2] = thread.entries
      assert is_binary(e1.id)
      assert is_binary(e2.id)
      assert String.starts_with?(e1.id, "entry_")
      assert String.starts_with?(e2.id, "entry_")
      refute e1.id == e2.id
    end

    test "entries get timestamps assigned" do
      opts = [table: unique_table(:entry_timestamps)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      before = System.system_time(:millisecond)
      {:ok, thread} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      after_append = System.system_time(:millisecond)

      entry = hd(thread.entries)
      assert is_integer(entry.at)
      assert entry.at >= before
      assert entry.at <= after_append
    end

    test "thread metadata is preserved" do
      opts = [table: unique_table(:metadata), metadata: %{user_id: "u123", session: "s456"}]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      {:ok, thread} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert thread.metadata == %{user_id: "u123", session: "s456"}

      {:ok, loaded} = ETS.load_thread(thread_id, opts)
      assert loaded.metadata == %{user_id: "u123", session: "s456"}
    end

    test "thread has created_at and updated_at timestamps" do
      opts = [table: unique_table(:thread_timestamps)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      before = System.system_time(:millisecond)
      {:ok, thread} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      after_create = System.system_time(:millisecond)

      assert is_integer(thread.created_at)
      assert is_integer(thread.updated_at)
      assert thread.created_at >= before
      assert thread.created_at <= after_create
      assert thread.updated_at >= thread.created_at

      Process.sleep(2)

      {:ok, updated} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert updated.created_at == thread.created_at
      assert updated.updated_at >= thread.updated_at
    end

    test "accepts Entry structs directly" do
      opts = [table: unique_table(:entry_structs)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      entry = Entry.new(kind: :message, payload: %{role: "user", content: "Hello"})

      {:ok, thread} = ETS.append_thread(thread_id, [entry], opts)
      assert length(thread.entries) == 1
      assert hd(thread.entries).kind == :message
    end

    test "stats include entry_count" do
      opts = [table: unique_table(:stats)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      {:ok, thread} =
        ETS.append_thread(thread_id, [%{kind: :note}, %{kind: :note}, %{kind: :note}], opts)

      assert thread.stats.entry_count == 3
    end
  end

  describe "table isolation" do
    test "different table names are isolated" do
      opts1 = [table: unique_table(:isolation1)]
      opts2 = [table: unique_table(:isolation2)]

      assert :ok = ETS.put_checkpoint(:shared_key, :value1, opts1)
      assert :ok = ETS.put_checkpoint(:shared_key, :value2, opts2)

      assert {:ok, :value1} = ETS.get_checkpoint(:shared_key, opts1)
      assert {:ok, :value2} = ETS.get_checkpoint(:shared_key, opts2)
    end

    test "checkpoints and threads use separate tables" do
      opts = [table: unique_table(:separate_tables)]

      assert :ok = ETS.put_checkpoint("key1", :checkpoint_data, opts)
      {:ok, _} = ETS.append_thread("key1", [%{kind: :note}], opts)

      assert {:ok, :checkpoint_data} = ETS.get_checkpoint("key1", opts)
      assert {:ok, %Thread{}} = ETS.load_thread("key1", opts)
    end
  end
end
