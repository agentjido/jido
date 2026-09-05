defmodule JidoTest.RuntimeStoreTest do
  use JidoTest.Case, async: true

  alias Jido.RuntimeStore

  test "a stopped worker returns the fallback for each operation", %{jido: jido} do
    assert :ok = Supervisor.terminate_child(jido, Jido.runtime_store_name(jido))

    for {call, fallback} <- calls(jido) do
      assert call.() == fallback
    end
  end

  test "a normal exit during a call returns each operation's fallback", %{jido: jido} do
    assert :ok = Supervisor.terminate_child(jido, Jido.runtime_store_name(jido))

    for {call, fallback} <- calls(jido) do
      worker = start_call_worker(jido)
      task = Task.async(call)
      assert_receive {:request, ^worker, _request}, 1_000
      ref = Process.monitor(worker)
      send(worker, {:exit, :normal})
      assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 1_000
      assert Task.await(task) == fallback
    end
  end

  test "an abnormal worker exit reaches the caller", %{jido: jido} do
    assert :ok = Supervisor.terminate_child(jido, Jido.runtime_store_name(jido))
    worker = start_call_worker(jido)
    task = Task.async(fn -> catch_exit(RuntimeStore.fetch(jido, :hive, :key)) end)
    assert_receive {:request, ^worker, _request}, 1_000
    send(worker, {:exit, :shutdown})
    assert {:shutdown, {GenServer, :call, _}} = Task.await(task)
  end

  test "a write timeout propagates even when the worker later completes it", %{jido: jido} do
    assert :ok = Supervisor.terminate_child(jido, Jido.runtime_store_name(jido))
    worker = start_call_worker(jido)
    task = Task.async(fn -> catch_exit(RuntimeStore.put(jido, :hive, :key, :value)) end)
    assert_receive {:request, ^worker, {:put, :hive, :key, :value}}, 1_000
    assert {:timeout, {GenServer, :call, _}} = Task.await(task, 6_000)
    send(worker, :complete)
    assert_receive {:completed, ^worker}, 1_000
    assert [{{:hive, :key}, :value}] = :ets.lookup(Jido.runtime_store_name(jido), {:hive, :key})
  end

  defp calls(jido) do
    [
      {fn -> RuntimeStore.fetch(jido, :hive, :key) end, :error},
      {fn -> RuntimeStore.get(jido, :hive, :key, :default) end, :default},
      {fn -> RuntimeStore.put(jido, :hive, :key, :value) end, {:error, :not_running}},
      {fn -> RuntimeStore.delete(jido, :hive, :key) end, {:error, :not_running}},
      {fn -> RuntimeStore.list(jido, :hive) end, []}
    ]
  end

  defp start_call_worker(jido) do
    observer = self()

    worker =
      spawn(fn ->
        receive do
          {:"$gen_call", from, request} ->
            send(observer, {:request, self(), request})

            receive do
              {:exit, reason} ->
                exit(reason)

              :complete ->
                {:put, hive, key, value} = request
                :ets.insert(Jido.runtime_store_name(jido), {{hive, key}, value})
                GenServer.reply(from, :ok)
                send(observer, {:completed, self()})
            after
              10_000 -> exit(:barrier_timeout)
            end
        after
          10_000 -> exit(:request_timeout)
        end
      end)

    on_exit(fn -> Process.exit(worker, :kill) end)
    Process.register(worker, Jido.runtime_store_name(jido))
    worker
  end

  describe "RuntimeStore" do
    test "supports put/get/fetch/delete within a hive", %{jido: jido} do
      assert :error == RuntimeStore.fetch(jido, :relationships, "child-1")
      assert nil == RuntimeStore.get(jido, :relationships, "child-1")
      assert :missing == RuntimeStore.get(jido, :relationships, "child-1", :missing)

      assert :ok ==
               RuntimeStore.put(jido, :relationships, "child-1", %{
                 parent_id: "parent-1",
                 tag: :worker
               })

      assert {:ok, %{parent_id: "parent-1", tag: :worker}} =
               RuntimeStore.fetch(jido, :relationships, "child-1")

      assert %{parent_id: "parent-1", tag: :worker} ==
               RuntimeStore.get(jido, :relationships, "child-1")

      assert :ok == RuntimeStore.delete(jido, :relationships, "child-1")
      assert :error == RuntimeStore.fetch(jido, :relationships, "child-1")
    end

    test "keeps hives isolated", %{jido: jido} do
      assert :ok == RuntimeStore.put(jido, :relationships, "child-1", %{parent_id: "parent-1"})
      assert :ok == RuntimeStore.put(jido, :runtime_flags, :orphan_mode, true)

      assert [orphan_mode: true] == Enum.sort(RuntimeStore.list(jido, :runtime_flags))
      assert [{"child-1", %{parent_id: "parent-1"}}] == RuntimeStore.list(jido, :relationships)
    end

    test "retains entries when the RuntimeStore process restarts", %{jido: jido} do
      runtime_store = Jido.runtime_store_name(jido)
      runtime_store_pid = Process.whereis(runtime_store)
      runtime_store_ref = Process.monitor(runtime_store_pid)

      assert :ok ==
               RuntimeStore.put(jido, :relationships, "child-1", %{
                 parent_id: "parent-1",
                 tag: :worker
               })

      Process.exit(runtime_store_pid, :kill)
      assert_receive {:DOWN, ^runtime_store_ref, :process, ^runtime_store_pid, :killed}, 1_000

      eventually(fn ->
        case Process.whereis(runtime_store) do
          pid when is_pid(pid) -> pid != runtime_store_pid
          _ -> false
        end
      end)

      assert {:ok, %{parent_id: "parent-1", tag: :worker}} =
               RuntimeStore.fetch(jido, :relationships, "child-1")
    end
  end
end
