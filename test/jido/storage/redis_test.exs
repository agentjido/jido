defmodule JidoTest.Storage.RedisTest do
  use ExUnit.Case, async: true

  alias Jido.Storage
  alias Jido.Storage.Redis
  alias Jido.Thread

  @moduletag :unit

  # ---------------------------------------------------------------------------
  # Mock Redis backend using an Agent (per-test process for isolation)
  # ---------------------------------------------------------------------------

  defp start_mock_redis(_context \\ %{}) do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    pid
  end

  defp mock_command_fn(pid) do
    fn command ->
      case command do
        ["GET", key] ->
          {:ok, Agent.get(pid, fn state -> Map.get(state, key) end)}

        ["SET", key, value] ->
          Agent.update(pid, fn state -> Map.put(state, key, value) end)
          {:ok, "OK"}

        ["SET", key, value, "PX", _ttl] ->
          Agent.update(pid, fn state -> Map.put(state, key, value) end)
          {:ok, "OK"}

        ["DEL" | keys] ->
          count =
            Agent.get_and_update(pid, fn state ->
              deleted = Enum.count(keys, &Map.has_key?(state, &1))
              new_state = Map.drop(state, keys)
              {deleted, new_state}
            end)

          {:ok, count}

        _ ->
          {:error, :unknown_command}
      end
    end
  end

  defp redis_opts(pid, extra \\ []) do
    Keyword.merge([command_fn: mock_command_fn(pid)], extra)
  end

  # ---------------------------------------------------------------------------
  # Checkpoint Tests
  # ---------------------------------------------------------------------------

  describe "get_checkpoint/2" do
    test "returns :not_found when key does not exist" do
      pid = start_mock_redis()
      assert :not_found = Redis.get_checkpoint(:missing, redis_opts(pid))
    end

    test "returns {:ok, data} for stored checkpoint" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      :ok = Redis.put_checkpoint(:my_key, %{counter: 42}, opts)
      assert {:ok, %{counter: 42}} = Redis.get_checkpoint(:my_key, opts)
    end

    test "returns :not_found after checkpoint is deleted" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      :ok = Redis.put_checkpoint(:del_key, %{val: 1}, opts)
      :ok = Redis.delete_checkpoint(:del_key, opts)
      assert :not_found = Redis.get_checkpoint(:del_key, opts)
    end
  end

  describe "put_checkpoint/3" do
    test "stores and retrieves complex data" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      data = %{
        version: 1,
        agent_module: SomeModule,
        id: "agent-1",
        state: %{counter: 100, status: :active, nested: %{a: [1, 2, 3]}},
        thread: %{id: "thread-1", rev: 5}
      }

      :ok = Redis.put_checkpoint({SomeModule, "agent-1"}, data, opts)
      assert {:ok, ^data} = Redis.get_checkpoint({SomeModule, "agent-1"}, opts)
    end

    test "overwrites existing checkpoint" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      :ok = Redis.put_checkpoint(:key, %{v: 1}, opts)
      :ok = Redis.put_checkpoint(:key, %{v: 2}, opts)
      assert {:ok, %{v: 2}} = Redis.get_checkpoint(:key, opts)
    end

    test "accepts TTL option" do
      pid = start_mock_redis()
      opts = redis_opts(pid, ttl: 60_000)

      :ok = Redis.put_checkpoint(:ttl_key, %{data: true}, opts)
      assert {:ok, %{data: true}} = Redis.get_checkpoint(:ttl_key, opts)
    end
  end

  describe "delete_checkpoint/2" do
    test "returns :ok for non-existent key" do
      pid = start_mock_redis()
      assert :ok = Redis.delete_checkpoint(:nope, redis_opts(pid))
    end

    test "removes existing checkpoint" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      :ok = Redis.put_checkpoint(:to_delete, %{x: 1}, opts)
      :ok = Redis.delete_checkpoint(:to_delete, opts)
      assert :not_found = Redis.get_checkpoint(:to_delete, opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Thread Tests
  # ---------------------------------------------------------------------------

  describe "load_thread/2" do
    test "returns :not_found when thread does not exist" do
      pid = start_mock_redis()
      assert :not_found = Redis.load_thread("missing-thread", redis_opts(pid))
    end

    test "loads thread after entries are appended" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _thread} =
        Redis.append_thread("th-1", [%{kind: :message, payload: %{content: "hi"}}], opts)

      assert {:ok, %Thread{id: "th-1", rev: 1}} = Redis.load_thread("th-1", opts)
    end
  end

  describe "append_thread/3" do
    test "creates new thread with entries" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      entries = [
        %{kind: :message, payload: %{role: "user", content: "hello"}},
        %{kind: :message, payload: %{role: "assistant", content: "hi"}}
      ]

      assert {:ok, %Thread{} = thread} = Redis.append_thread("new-th", entries, opts)
      assert thread.id == "new-th"
      assert thread.rev == 2
      assert length(thread.entries) == 2
    end

    test "appends to existing thread" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _} = Redis.append_thread("grow-th", [%{kind: :note, payload: %{text: "first"}}], opts)

      {:ok, thread} =
        Redis.append_thread("grow-th", [%{kind: :note, payload: %{text: "second"}}], opts)

      assert thread.rev == 2
      assert length(thread.entries) == 2
    end

    test "expected_rev succeeds when matching" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _} = Redis.append_thread("rev-th", [%{kind: :note}], opts)

      assert {:ok, %Thread{rev: 2}} =
               Redis.append_thread(
                 "rev-th",
                 [%{kind: :note}],
                 Keyword.put(opts, :expected_rev, 1)
               )
    end

    test "expected_rev fails with :conflict when mismatched" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _} = Redis.append_thread("conflict-th", [%{kind: :note}], opts)

      assert {:error, :conflict} =
               Redis.append_thread(
                 "conflict-th",
                 [%{kind: :note}],
                 Keyword.put(opts, :expected_rev, 0)
               )
    end

    test "expected_rev 0 succeeds for new thread" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      assert {:ok, %Thread{rev: 1}} =
               Redis.append_thread(
                 "fresh-th",
                 [%{kind: :note}],
                 Keyword.put(opts, :expected_rev, 0)
               )
    end

    test "entries get monotonic sequence numbers" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, thread} =
        Redis.append_thread(
          "seq-th",
          [%{kind: :note}, %{kind: :note}, %{kind: :note}],
          opts
        )

      seqs = Enum.map(thread.entries, & &1.seq)
      assert seqs == [0, 1, 2]
    end

    test "appended entries continue sequence" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _} = Redis.append_thread("seq2-th", [%{kind: :note}, %{kind: :note}], opts)
      {:ok, thread} = Redis.append_thread("seq2-th", [%{kind: :note}], opts)

      seqs = Enum.map(thread.entries, & &1.seq)
      assert seqs == [0, 1, 2]
    end

    test "thread metadata is set for new threads" do
      pid = start_mock_redis()
      opts = Keyword.put(redis_opts(pid), :metadata, %{source: "test"})

      {:ok, thread} = Redis.append_thread("meta-th", [%{kind: :note}], opts)
      assert thread.metadata == %{source: "test"}
    end
  end

  describe "delete_thread/2" do
    test "returns :ok for non-existent thread" do
      pid = start_mock_redis()
      assert :ok = Redis.delete_thread("nope-th", redis_opts(pid))
    end

    test "removes existing thread" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      {:ok, _} = Redis.append_thread("del-th", [%{kind: :note}], opts)
      :ok = Redis.delete_thread("del-th", opts)
      assert :not_found = Redis.load_thread("del-th", opts)
    end
  end

  # ---------------------------------------------------------------------------
  # Key Prefixing
  # ---------------------------------------------------------------------------

  describe "key prefixing" do
    test "different prefixes create isolated namespaces" do
      pid = start_mock_redis()
      opts_a = redis_opts(pid, prefix: "ns_a")
      opts_b = redis_opts(pid, prefix: "ns_b")

      :ok = Redis.put_checkpoint(:shared_key, %{from: :a}, opts_a)
      :ok = Redis.put_checkpoint(:shared_key, %{from: :b}, opts_b)

      assert {:ok, %{from: :a}} = Redis.get_checkpoint(:shared_key, opts_a)
      assert {:ok, %{from: :b}} = Redis.get_checkpoint(:shared_key, opts_b)
    end

    test "thread isolation between prefixes" do
      pid = start_mock_redis()
      opts_a = redis_opts(pid, prefix: "ns_a")
      opts_b = redis_opts(pid, prefix: "ns_b")

      {:ok, _} = Redis.append_thread("th-1", [%{kind: :note, payload: %{ns: "a"}}], opts_a)
      {:ok, _} = Redis.append_thread("th-1", [%{kind: :note, payload: %{ns: "b"}}], opts_b)

      {:ok, thread_a} = Redis.load_thread("th-1", opts_a)
      {:ok, thread_b} = Redis.load_thread("th-1", opts_b)

      assert Enum.at(thread_a.entries, 0).payload.ns == "a"
      assert Enum.at(thread_b.entries, 0).payload.ns == "b"
    end
  end

  # ---------------------------------------------------------------------------
  # Round-Trip with Jido.Storage helpers
  # ---------------------------------------------------------------------------

  describe "Jido.Storage helper integration" do
    test "fetch_checkpoint normalizes :not_found" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      assert {:error, :not_found} = Storage.fetch_checkpoint(Redis, :missing, opts)
    end

    test "fetch_thread normalizes :not_found" do
      pid = start_mock_redis()
      opts = redis_opts(pid)

      assert {:error, :not_found} = Storage.fetch_thread(Redis, "nope", opts)
    end

    test "normalize_storage works with Redis module" do
      assert {Redis, []} = Storage.normalize_storage(Redis)
      assert {Redis, [prefix: "x"]} = Storage.normalize_storage({Redis, prefix: "x"})
    end
  end

  # ---------------------------------------------------------------------------
  # Error Handling
  # ---------------------------------------------------------------------------

  describe "error handling" do
    test "raises ArgumentError when command_fn is missing" do
      assert_raise ArgumentError, ~r/requires a :command_fn/, fn ->
        Redis.get_checkpoint(:key, [])
      end
    end

    test "propagates Redis errors on get_checkpoint" do
      failing_fn = fn _cmd -> {:error, :connection_closed} end
      opts = [command_fn: failing_fn]

      assert {:error, :connection_closed} = Redis.get_checkpoint(:key, opts)
    end

    test "propagates Redis errors on put_checkpoint" do
      failing_fn = fn _cmd -> {:error, :connection_closed} end
      opts = [command_fn: failing_fn]

      assert {:error, :connection_closed} = Redis.put_checkpoint(:key, %{}, opts)
    end

    test "propagates Redis errors on load_thread" do
      failing_fn = fn _cmd -> {:error, :connection_closed} end
      opts = [command_fn: failing_fn]

      assert {:error, :connection_closed} = Redis.load_thread("th", opts)
    end
  end
end
