defmodule JidoTest.Storage.FileTest do
  use ExUnit.Case, async: false

  alias Jido.Storage.File, as: FileStorage
  alias Jido.Thread
  alias Jido.Thread.Entry

  @moduletag :storage

  setup do
    base_dir =
      Path.join(
        System.tmp_dir!(),
        "jido_file_storage_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(base_dir)
    on_exit(fn -> File.rm_rf!(base_dir) end)
    {:ok, path: base_dir, opts: [path: base_dir]}
  end

  describe "checkpoint operations" do
    test "get_checkpoint/2 returns :not_found for missing key", %{opts: opts} do
      assert {:error, :not_found} = FileStorage.get_checkpoint(:missing_key, opts)
    end

    test "put_checkpoint/3 stores and get_checkpoint/2 retrieves data", %{opts: opts} do
      key = :my_checkpoint
      data = %{counter: 42, name: "test"}

      assert :ok = FileStorage.put_checkpoint(key, data, opts)
      assert {:ok, ^data} = FileStorage.get_checkpoint(key, opts)
    end

    test "put_checkpoint/3 overwrites existing data atomically", %{opts: opts} do
      key = :overwrite_test

      assert :ok = FileStorage.put_checkpoint(key, %{version: 1}, opts)
      assert {:ok, %{version: 1}} = FileStorage.get_checkpoint(key, opts)

      assert :ok = FileStorage.put_checkpoint(key, %{version: 2}, opts)
      assert {:ok, %{version: 2}} = FileStorage.get_checkpoint(key, opts)
    end

    test "delete_checkpoint/2 removes data", %{opts: opts} do
      key = :to_delete

      assert :ok = FileStorage.put_checkpoint(key, %{data: "exists"}, opts)
      assert {:ok, _} = FileStorage.get_checkpoint(key, opts)

      assert :ok = FileStorage.delete_checkpoint(key, opts)
      assert {:error, :not_found} = FileStorage.get_checkpoint(key, opts)
    end

    test "delete_checkpoint/2 succeeds even if key doesn't exist", %{opts: opts} do
      assert :ok = FileStorage.delete_checkpoint(:nonexistent_key, opts)
    end

    test "data survives serialization/deserialization correctly", %{opts: opts} do
      key = :complex_data

      complex_data = %{
        string: "hello",
        integer: 123,
        float: 3.14,
        atom: :some_atom,
        list: [1, 2, 3],
        tuple: {:ok, "value"},
        nested: %{
          deep: %{value: true}
        },
        binary: <<1, 2, 3, 4, 5>>
      }

      assert :ok = FileStorage.put_checkpoint(key, complex_data, opts)
      assert {:ok, retrieved} = FileStorage.get_checkpoint(key, opts)

      assert retrieved.string == "hello"
      assert retrieved.integer == 123
      assert retrieved.float == 3.14
      assert retrieved.atom == :some_atom
      assert retrieved.list == [1, 2, 3]
      assert retrieved.tuple == {:ok, "value"}
      assert retrieved.nested == %{deep: %{value: true}}
      assert retrieved.binary == <<1, 2, 3, 4, 5>>
    end
  end

  describe "thread operations" do
    test "load_thread/2 returns :not_found for missing thread", %{opts: opts} do
      assert {:error, :not_found} = FileStorage.load_thread("nonexistent_thread", opts)
    end

    test "append_thread/3 creates thread with entries", %{opts: opts} do
      thread_id = "new_thread_#{:erlang.unique_integer([:positive])}"

      entry = %Entry{
        id: "entry_1",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{role: "user", content: "Hello"},
        refs: %{}
      }

      assert {:ok, thread} = FileStorage.append_thread(thread_id, [entry], opts)
      assert thread.id == thread_id
      assert thread.rev == 1
      assert length(thread.entries) == 1
      assert hd(thread.entries).kind == :message
    end

    test "append_thread/3 appends to existing thread", %{opts: opts} do
      thread_id = "append_test_#{:erlang.unique_integer([:positive])}"

      entry1 = %Entry{
        id: "entry_1",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{role: "user", content: "First"},
        refs: %{}
      }

      assert {:ok, thread1} = FileStorage.append_thread(thread_id, [entry1], opts)
      assert thread1.rev == 1

      entry2 = %Entry{
        id: "entry_2",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{role: "assistant", content: "Second"},
        refs: %{}
      }

      assert {:ok, thread2} = FileStorage.append_thread(thread_id, [entry2], opts)
      assert thread2.rev == 2
      assert length(thread2.entries) == 2
      assert Enum.at(thread2.entries, 0).payload.content == "First"
      assert Enum.at(thread2.entries, 1).payload.content == "Second"
    end

    test "append_thread/3 with expected_rev: succeeds when rev matches", %{opts: opts} do
      thread_id = "expected_rev_success_#{:erlang.unique_integer([:positive])}"

      entry1 = %Entry{
        id: "entry_1",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{content: "First"},
        refs: %{}
      }

      {:ok, _thread1} = FileStorage.append_thread(thread_id, [entry1], opts)

      entry2 = %Entry{
        id: "entry_2",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{content: "Second"},
        refs: %{}
      }

      opts_with_rev = Keyword.put(opts, :expected_rev, 1)
      assert {:ok, thread2} = FileStorage.append_thread(thread_id, [entry2], opts_with_rev)
      assert thread2.rev == 2
    end

    test "append_thread/3 with expected_rev: returns {:error, :conflict} when rev doesn't match",
         %{opts: opts} do
      thread_id = "expected_rev_conflict_#{:erlang.unique_integer([:positive])}"

      entry1 = %Entry{
        id: "entry_1",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{content: "First"},
        refs: %{}
      }

      {:ok, _thread1} = FileStorage.append_thread(thread_id, [entry1], opts)

      entry2 = %Entry{
        id: "entry_2",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{content: "Second"},
        refs: %{}
      }

      opts_with_wrong_rev = Keyword.put(opts, :expected_rev, 0)

      assert {:error, :conflict} =
               FileStorage.append_thread(thread_id, [entry2], opts_with_wrong_rev)
    end

    test "load_thread/2 returns correct %Jido.Thread{} with all entries", %{opts: opts} do
      thread_id = "load_test_#{:erlang.unique_integer([:positive])}"

      entries =
        for i <- 1..3 do
          %Entry{
            id: "entry_#{i}",
            seq: 0,
            at: System.system_time(:millisecond),
            kind: :message,
            payload: %{index: i},
            refs: %{}
          }
        end

      {:ok, _thread} = FileStorage.append_thread(thread_id, entries, opts)
      {:ok, loaded} = FileStorage.load_thread(thread_id, opts)

      assert %Thread{} = loaded
      assert loaded.id == thread_id
      assert loaded.rev == 3
      assert length(loaded.entries) == 3
      assert loaded.stats.entry_count == 3

      for {entry, idx} <- Enum.with_index(loaded.entries) do
        assert entry.seq == idx
        assert entry.payload.index == idx + 1
      end
    end

    test "delete_thread/2 removes thread directory and all files", %{opts: opts} do
      thread_id = "delete_test_#{:erlang.unique_integer([:positive])}"
      path = Keyword.fetch!(opts, :path)

      entry = %Entry{
        id: "entry_1",
        seq: 0,
        at: System.system_time(:millisecond),
        kind: :message,
        payload: %{content: "test"},
        refs: %{}
      }

      {:ok, _thread} = FileStorage.append_thread(thread_id, [entry], opts)

      thread_dir = Path.join([path, "threads", thread_id])
      assert File.exists?(thread_dir)

      assert :ok = FileStorage.delete_thread(thread_id, opts)
      refute File.exists?(thread_dir)
      assert {:error, :not_found} = FileStorage.load_thread(thread_id, opts)
    end

    test "thread entries have correct seq numbers", %{opts: opts} do
      thread_id = "seq_test_#{:erlang.unique_integer([:positive])}"

      entry1 = %Entry{id: "e1", seq: 0, at: 0, kind: :message, payload: %{}, refs: %{}}
      {:ok, _} = FileStorage.append_thread(thread_id, [entry1], opts)

      entry2 = %Entry{id: "e2", seq: 0, at: 0, kind: :message, payload: %{}, refs: %{}}
      entry3 = %Entry{id: "e3", seq: 0, at: 0, kind: :message, payload: %{}, refs: %{}}
      {:ok, thread} = FileStorage.append_thread(thread_id, [entry2, entry3], opts)

      assert Enum.at(thread.entries, 0).seq == 0
      assert Enum.at(thread.entries, 1).seq == 1
      assert Enum.at(thread.entries, 2).seq == 2
    end

    test "binary framing handles various entry sizes correctly", %{opts: opts} do
      thread_id = "framing_test_#{:erlang.unique_integer([:positive])}"

      small_entry = %Entry{
        id: "small",
        seq: 0,
        at: 0,
        kind: :message,
        payload: %{data: "x"},
        refs: %{}
      }

      medium_entry = %Entry{
        id: "medium",
        seq: 0,
        at: 0,
        kind: :message,
        payload: %{data: String.duplicate("y", 1000)},
        refs: %{}
      }

      large_entry = %Entry{
        id: "large",
        seq: 0,
        at: 0,
        kind: :message,
        payload: %{data: String.duplicate("z", 100_000)},
        refs: %{}
      }

      {:ok, _} = FileStorage.append_thread(thread_id, [small_entry], opts)
      {:ok, _} = FileStorage.append_thread(thread_id, [medium_entry], opts)
      {:ok, thread} = FileStorage.append_thread(thread_id, [large_entry], opts)

      assert length(thread.entries) == 3
      assert Enum.at(thread.entries, 0).payload.data == "x"
      assert Enum.at(thread.entries, 1).payload.data == String.duplicate("y", 1000)
      assert Enum.at(thread.entries, 2).payload.data == String.duplicate("z", 100_000)

      {:ok, loaded} = FileStorage.load_thread(thread_id, opts)
      assert length(loaded.entries) == 3
      assert Enum.at(loaded.entries, 2).payload.data == String.duplicate("z", 100_000)
    end
  end

  describe "edge cases" do
    test "handles special characters in keys", %{opts: opts} do
      special_keys = [
        "key with spaces",
        "key/with/slashes",
        "key:with:colons",
        "key\twith\ttabs",
        "key🎉with🎉emoji",
        {:tuple, "key"},
        ["list", "key"]
      ]

      for key <- special_keys do
        data = %{key: inspect(key)}
        assert :ok = FileStorage.put_checkpoint(key, data, opts)
        assert {:ok, ^data} = FileStorage.get_checkpoint(key, opts)
      end
    end

    test "handles empty entries list", %{opts: opts} do
      thread_id = "empty_entries_#{:erlang.unique_integer([:positive])}"

      entry = %Entry{id: "e1", seq: 0, at: 0, kind: :message, payload: %{}, refs: %{}}
      {:ok, _} = FileStorage.append_thread(thread_id, [entry], opts)

      {:ok, thread} = FileStorage.append_thread(thread_id, [], opts)
      assert length(thread.entries) == 1
      assert thread.rev == 1
    end

    test "handles large payloads", %{opts: opts} do
      large_data = %{
        blob: :crypto.strong_rand_bytes(1_000_000),
        list: Enum.to_list(1..10_000)
      }

      assert :ok = FileStorage.put_checkpoint(:large_checkpoint, large_data, opts)
      assert {:ok, retrieved} = FileStorage.get_checkpoint(:large_checkpoint, opts)
      assert byte_size(retrieved.blob) == 1_000_000
      assert length(retrieved.list) == 10_000
    end

    test "handles thread with many entries", %{opts: opts} do
      thread_id = "many_entries_#{:erlang.unique_integer([:positive])}"

      entries =
        for i <- 1..100 do
          %Entry{
            id: "entry_#{i}",
            seq: 0,
            at: System.system_time(:millisecond),
            kind: :message,
            payload: %{index: i, data: String.duplicate("x", 100)},
            refs: %{}
          }
        end

      {:ok, thread} = FileStorage.append_thread(thread_id, entries, opts)
      assert thread.rev == 100
      assert length(thread.entries) == 100

      {:ok, loaded} = FileStorage.load_thread(thread_id, opts)
      assert length(loaded.entries) == 100

      for {entry, idx} <- Enum.with_index(loaded.entries) do
        assert entry.seq == idx
      end
    end

    test "handles concurrent appends to different threads", %{opts: opts} do
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            thread_id = "concurrent_#{i}"

            entry = %Entry{
              id: "entry_#{i}",
              seq: 0,
              at: System.system_time(:millisecond),
              kind: :message,
              payload: %{thread: i},
              refs: %{}
            }

            {:ok, thread} = FileStorage.append_thread(thread_id, [entry], opts)
            {thread_id, thread}
          end)
        end

      results = Task.await_many(tasks, 5000)

      for {thread_id, thread} <- results do
        assert thread.id == thread_id
        assert thread.rev == 1
      end
    end

    test "handles nil values in payload", %{opts: opts} do
      key = :nil_payload

      data = %{
        value: nil,
        nested: %{inner: nil},
        list: [nil, 1, nil]
      }

      assert :ok = FileStorage.put_checkpoint(key, data, opts)
      assert {:ok, retrieved} = FileStorage.get_checkpoint(key, opts)
      assert retrieved.value == nil
      assert retrieved.nested.inner == nil
      assert retrieved.list == [nil, 1, nil]
    end
  end
end
