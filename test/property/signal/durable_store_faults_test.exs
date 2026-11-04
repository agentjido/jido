Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("support/runtime.exs", __DIR__)
Code.require_file("support/fault_store.exs", __DIR__)

defmodule JidoTest.Property.Signal.DurableStoreFaultsTest do
  use ExUnit.Case, async: true
  import StreamData
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Store.Memory
  alias JidoTest.Property.Fuzz
  alias JidoTest.Property.Signal.{FaultStore, Model, Runtime}

  @times [
    "2026-09-29T00:00:00Z",
    "2026-09-29T01:00:00+01:00",
    "2026-09-29T00:00:00+00:00",
    "2026-09-29T00:00:00.1234567Z"
  ]
  @faults ~w(error invalid raise throw exit)
  for {suite, runs} <- [property: 40, fuzz: 500] do
    @tag [
      {suite, true},
      fuzz_id: "durable_store_faults",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: Store failure and durable recovery", context do
      generator = fixed_map(%{"fault" => member_of(@faults), "time" => member_of(@times)})
      examples = for fault <- @faults, time <- @times, do: %{"fault" => fault, "time" => time}

      Fuzz.check(
        "durable_store_faults",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{"fault" => fault, "time" => time}) do
    token = make_ref()
    owner = self()
    assert {:ok, memory} = Memory.init([])
    definition = Model.definition("restored", "event.**", 0) |> Map.put("created_at", time)
    assert {:ok, memory} = Memory.put_subscription(definition, memory)

    assert {:ok, agent} =
             Agent.start_link(fn ->
               %{memory: memory, faults: %{}, owner: owner, token: token, gate: false}
             end)

    opts = [store: FaultStore, store_opts: [agent: agent]]

    try do
      callback_boundaries(agent, fault)

      Runtime.with_bus(opts, fn %{bus: bus} ->
        assert {:ok, "restored"} = Bus.subscribe(bus, "event.**", durable: "restored")
        signal = Signal.new!("event.a", %{"_probe" => token}, source: "/property")
        snapshot = FaultStore.snapshot(agent)
        FaultStore.fail(agent, :append, fault)
        assert_fault(Bus.publish(bus, [signal]), :append, fault)
        assert FaultStore.snapshot(agent) == snapshot
        refute_received {:signal, "restored", _}
        assert {:ok, []} = Bus.replay(bus)

        FaultStore.gate_append(agent)
        task = Task.async(fn -> Bus.publish(bus, [signal, signal]) end)

        try do
          assert_receive {^token, :append_held, ^bus}, 5_000
          assert FaultStore.snapshot(agent) == snapshot
          refute_received {:signal, "restored", _}
          send(bus, {token, :release_append})
          assert {:ok, [first, second]} = Task.await(task)
          assert {first.cursor, second.cursor} == {1, 2}
          assert_received {:signal, "restored", delivered}
          assert delivered.cursor == 1
        after
          send(bus, {token, :release_append})
          if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
        end

        snapshot = FaultStore.snapshot(agent)
        FaultStore.fail(agent, :put_subscription, fault)
        assert_fault(Bus.ack(bus, "restored", 1), :put_subscription, fault)
        assert FaultStore.snapshot(agent) == snapshot
        refute_received {:signal, "restored", _}
        assert :ok = Bus.ack(bus, "restored", 1)
        assert_received {:signal, "restored", delivered}
        assert delivered.cursor == 2

        assert {:ok, [%{"created_at" => ^time, "cursor" => 1}]} =
                 Memory.list_subscriptions(FaultStore.snapshot(agent))

        snapshot = FaultStore.snapshot(agent)
        FaultStore.fail(agent, :put_subscription, fault)
        assert_fault(Bus.subscribe(bus, "**", durable: "new"), :put_subscription, fault)
        assert FaultStore.snapshot(agent) == snapshot
        assert {:error, :subscription_not_found} = Bus.ack(bus, "new", 0)
        FaultStore.fail(agent, :delete_subscription, fault)
        assert_fault(Bus.delete_subscription(bus, "restored"), :delete_subscription, fault)
        assert FaultStore.snapshot(agent) == snapshot

        FaultStore.fail(agent, :read, fault)
        assert_fault(Bus.replay(bus), :read, fault)

        for malformed <- ["improper", "bad-record"] do
          FaultStore.fail(agent, :read, malformed)
          assert {:error, _} = Bus.replay(bus)
          assert :ok = Bus.unsubscribe(bus, "restored")
          FaultStore.fail(agent, :read, malformed)
          assert {:ok, "restored"} = Bus.subscribe(bus, "event.**", durable: "restored")
          refute_received {:signal, "restored", _}
        end
      end)

      assert Process.alive?(agent)

      Runtime.with_bus(opts, fn %{bus: bus} ->
        assert {:ok, "restored"} = Bus.subscribe(bus, "event.**", durable: "restored")
        assert_received {:signal, "restored", delivered}
        assert delivered.cursor == 2
        assert :ok = Bus.ack(bus, "restored", 2)

        assert {:ok, [%{"created_at" => ^time, "cursor" => 2}]} =
                 Memory.list_subscriptions(FaultStore.snapshot(agent))

        assert :ok = Bus.delete_subscription(bus, "restored")
      end)

      assert Process.alive?(agent)
    after
      Runtime.stop(agent)
      Runtime.drain(token)
    end

    ["fault-#{fault}", "timestamp-#{time}"]
  end

  defp callback_boundaries(agent, fault) do
    for callback <- [:read, :latest_cursor, :list_subscriptions] do
      FaultStore.fail(agent, callback, fault)
      args = if callback == :read, do: [[]], else: []
      assert_fault(Store.read(FaultStore, agent, callback, args), callback, fault)
    end

    FaultStore.fail(agent, :init, fault)
    assert {:error, {:store_init_failed, reason}} = Store.init_adapter(FaultStore, agent: agent)
    check_reason(reason, fault)
  end

  defp assert_fault(result, callback, fault) do
    assert {:error, {:store_error, ^callback, reason}} = result
    check_reason(reason, fault)
  end

  defp check_reason(reason, "error"), do: assert(reason == :injected)
  defp check_reason(reason, "invalid"), do: assert(reason == {:invalid_return, :invalid_return})

  defp check_reason(reason, "raise"),
    do: assert(match?({:exception, %RuntimeError{message: "store fault"}}, reason))

  defp check_reason(reason, "throw"), do: assert(reason == {:throw, :injected})
  defp check_reason(reason, "exit"), do: assert(reason == {:exit, :injected})
end
