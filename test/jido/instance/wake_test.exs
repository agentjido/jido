defmodule Jido.Instance.WakeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Persistence.ETS
  alias Jido.Persistence.WakeStore
  alias Jido.Test.Persistence.FaultAdapter

  defmodule IndexRaceAdapter do
    @behaviour Jido.Persistence.Store

    def validate_options(opts) do
      keys = Keyword.keys(opts)

      if Keyword.keyword?(opts) and keys -- [:table, :controller] == [] and
           keys -- Enum.uniq(keys) == [] and is_atom(Keyword.get(opts, :table)) and
           is_pid(Keyword.get(opts, :controller)),
         do: :ok,
         else: {:error, :invalid_options}
    end

    def get(key, opts), do: ETS.get(key, delegate_options(opts))
    def put(key, value, opts), do: ETS.put(key, value, delegate_options(opts))
    def delete(key, opts), do: ETS.delete(key, delegate_options(opts))

    def compare_and_swap(key, expected, value, opts) do
      if String.ends_with?(key, ":index") and empty_index?(value) do
        controller = Keyword.fetch!(opts, :controller)
        send(controller, {:wake_index_remove, self()})

        receive do
          :continue_wake_index_remove -> :ok
        after
          5_000 -> raise "wake index race test timed out"
        end
      end

      ETS.compare_and_swap(key, expected, value, delegate_options(opts))
    end

    defp empty_index?(value) do
      match?(
        {:ok, %{format: 3, buckets: buckets}} when map_size(buckets) == 0,
        Jido.Persistence.Codec.Term.decode(value, [])
      )
    end

    defp delegate_options(opts), do: Keyword.take(opts, [:table])
  end

  defmodule Finish do
    use Jido.Action, name: "wake_test_finish"

    def run(_params, _context), do: {:ok, %{finished: true}}
  end

  defmodule ConsecutiveTimers do
    use Jido.Flow, name: "wake_test_consecutive_timers"

    flow do
      timer "first", after_ms: 40
      timer "second", after_ms: 40, needs: ["first"]
      step "finish", action: Finish, params: %{}, needs: ["second"]
      output result("finish")
    end
  end

  defmodule TimedAgent do
    use Jido.Agent, name: "wake_test_timed_agent"

    state do
      schema Jido.Joi.object(%{finished: Jido.Joi.boolean() |> Jido.Joi.default(false)})
    end

    routes do
      route "test.wake.start", ConsecutiveTimers do
      end
    end
  end

  @tag obligation: "jido.persistence.I17"
  test "a wake can register the next wait in the same durable Turn" do
    {instance, address} = start_timed_agent()
    signal = Jido.Signal.new!("test.wake.start", %{}, source: "/test/wake")

    assert {:ok, %{status: :waiting, durability: :durable}} =
             Jido.call(instance, address, signal, turn_id: "two-wakes", result_handoff: true)

    assert_eventually(
      fn ->
        match?({:ok, _result}, Jido.turn_result(instance, address, "two-wakes"))
      end,
      160
    )

    assert {:ok, %{status: :committed, agent_revision: 1}} = Jido.turn_result(instance, address, "two-wakes")
    assert_eventually(fn -> WakeStore.list(instance) == {:ok, []} end)
  end

  @tag obligation: "jido.persistence.I17"
  test "a failed wake index write cannot acknowledge a durable wait" do
    {instance, address, control} = start_timed_agent_with_fault()
    index = "jido:wake:v3:" <> Base.url_encode64(address.namespace, padding: false) <> ":index"
    FaultAdapter.configure(control, {:write_error, index, :temporary})
    signal = Jido.Signal.new!("test.wake.start", %{}, source: "/test/wake")
    result = Jido.call(instance, address, signal, turn_id: "failed-wake", result_handoff: true)
    refute match?({:ok, %{status: :waiting, durability: :durable}}, result)
  end

  @tag obligation: "jido.persistence.I17"
  test "an orphan wake does not start a new Turn on an idle Agent" do
    {instance, address} = start_timed_agent()

    orphan =
      Jido.Signal.new!("jido.durable.wake", %{turn_id: "lost", wait_id: "lost", deadline: 0}, source: "/test/wake")

    assert {:error, :stale_wait} = Jido.call(instance, address, orphan)
    assert %{agent_revision: 0, work_state: :idle} = Jido.status(instance, address)
  end

  defp start_timed_agent do
    {instance, address, _control} = start_timed_agent_with_fault()
    {instance, address}
  end

  defp start_timed_agent_with_fault do
    suffix = System.unique_integer([:positive])
    instance = :"jido_two_wakes_#{suffix}"
    namespace = "two-wakes-#{suffix}"
    {:ok, control} = start_supervised(FaultAdapter)
    profile = {FaultAdapter, delegate: {ETS, table: :"jido_two_wakes_store_#{suffix}"}, control: control}
    start_supervised!({Jido, name: instance, namespace: namespace, persistence: profile})
    {:ok, address} = Jido.agent_address(instance, "timer")
    assert {:ok, ^address} = Jido.create_agent(instance, address, TimedAgent)
    {instance, address, control}
  end

  @tag obligation: "jido.persistence.I17"
  test "instance readiness waits for a retried wake recovery read" do
    suffix = System.unique_integer([:positive])
    instance = String.to_atom("jido_wake_retry_#{suffix}")
    namespace = "wake-retry-#{suffix}"
    {:ok, control} = start_supervised(FaultAdapter)

    profile =
      {FaultAdapter, delegate: {ETS, table: String.to_atom("wake_retry_store_#{suffix}")}, control: control}

    assert {:ok, _pid} =
             Jido.start_link(name: instance, namespace: namespace, persistence: profile)

    assert :ok = Jido.stop(instance)
    FaultAdapter.configure(control, {:read_error, "jido:wake:v3:", :temporary})

    log =
      capture_log(fn ->
        assert {:ok, _pid} =
                 Jido.start_link(name: instance, namespace: namespace, persistence: profile)
      end)

    assert log =~ "Jido wake recovery failed; retrying"
    assert :ok = Jido.stop(instance)
  end

  @tag obligation: "jido.persistence.I17"
  test "wake cleanup preserves index membership for a concurrent shard write" do
    suffix = System.unique_integer([:positive])
    instance = String.to_atom("jido_wake_index_race_#{suffix}")
    namespace = "wake-index-race-#{suffix}"
    table = String.to_atom("wake_index_race_store_#{suffix}")

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {IndexRaceAdapter, table: table, controller: self()}},
      id: {Jido, instance}
    )

    address = Jido.Agent.Address.new!(namespace: namespace, id: "agent")
    deadline = System.system_time(:millisecond) + 120_000
    old_entry = %{agent_address: address, turn_id: "old-turn", wait_id: "old-wait", deadline: deadline}
    new_entry = colliding_entry(address, old_entry, deadline)

    assert :ok = WakeStore.put(instance, [old_entry])
    delete_task = Task.async(fn -> WakeStore.delete(instance, old_entry) end)
    assert_receive {:wake_index_remove, delete_pid}, 1_000

    assert :ok = WakeStore.put(instance, [new_entry])
    send(delete_pid, :continue_wake_index_remove)
    assert :ok = Task.await(delete_task)
    assert {:ok, [^new_entry]} = WakeStore.list(instance)
  end

  @tag obligation: "jido.persistence.I17"
  test "wake cleanup retries a temporary Store failure" do
    suffix = System.unique_integer([:positive])
    instance = String.to_atom("jido_wake_cleanup_retry_#{suffix}")
    namespace = "wake-cleanup-retry-#{suffix}"
    {:ok, control} = start_supervised(FaultAdapter)

    profile =
      {FaultAdapter, delegate: {ETS, table: String.to_atom("wake_cleanup_retry_store_#{suffix}")}, control: control}

    start_supervised!({Jido, name: instance, namespace: namespace, persistence: profile},
      id: {Jido, instance}
    )

    address = Jido.Agent.Address.new!(namespace: namespace, id: "agent")

    entry = %{
      agent_address: address,
      turn_id: "turn",
      wait_id: "wait",
      deadline: System.system_time(:millisecond) + 120_000
    }

    assert :ok = WakeStore.put(instance, [entry])
    FaultAdapter.configure(control, {:write_error, "jido:wake:v3:", :temporary})

    log =
      capture_log(fn ->
        Jido.Instance.Wake.complete(instance, address, entry.turn_id)
        assert_eventually(fn -> WakeStore.list(instance) == {:ok, []} end)
      end)

    assert log =~ "Jido wake cleanup failed; retrying"
  end

  defp colliding_entry(address, old_entry, deadline) do
    target = shard(address, old_entry.turn_id, old_entry.wait_id)

    1
    |> Stream.iterate(&(&1 + 1))
    |> Enum.find_value(fn index ->
      turn_id = "new-turn-#{index}"
      wait_id = "new-wait-#{index}"

      if shard(address, turn_id, wait_id) == target,
        do: %{agent_address: address, turn_id: turn_id, wait_id: wait_id, deadline: deadline}
    end)
  end

  defp shard(address, turn_id, wait_id),
    do: :erlang.phash2({Jido.Agent.Address.to_map!(address), turn_id, wait_id}, 64)

  defp assert_eventually(fun, attempts \\ 40)

  defp assert_eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp assert_eventually(_fun, 0), do: flunk("condition did not become true")
end
