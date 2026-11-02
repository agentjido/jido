defmodule Jido.Signal.Bus.ModulePathTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal.Bus
  alias JidoSignalTest.Fixtures.Signals.UserCreated

  test "uses a Signal module for publication, replay, and ephemeral removal" do
    bus = start_supervised!({Bus, name: unique_name("module_path")})
    event = UserCreated.new!()
    assert {:ok, "module"} = Bus.subscribe(bus, UserCreated, subscription_id: "module")
    assert {:ok, [record]} = Bus.publish(bus, [event])
    assert_received {:signal, ^event}
    assert {:ok, [^record]} = Bus.replay(bus, UserCreated)
    assert {:ok, [^record]} = Bus.replay(bus, UserCreated.type())

    assert :ok = Bus.unsubscribe(bus, "module")
    assert {:ok, "module"} = Bus.subscribe(bus, UserCreated, subscription_id: "module")
    assert :ok = Bus.delete_subscription(bus, "module")
    assert {:ok, [_record]} = Bus.publish(bus, [event])
    refute_received {:signal, ^event}
    assert Process.alive?(bus)
  end

  test "treats a module and its type as the same durable path" do
    bus = start_supervised!({Bus, name: unique_name("durable_module")})
    event = UserCreated.new!()
    assert {:ok, "durable"} = Bus.subscribe(bus, UserCreated, durable: "durable")
    assert {:ok, "durable"} = Bus.subscribe(bus, UserCreated.type(), durable: "durable")
    assert :ok = Bus.unsubscribe(bus, "durable")
    assert {:ok, [record]} = Bus.publish(bus, [event])
    refute_received {:signal, "durable", _record}

    assert {:ok, "durable"} = Bus.subscribe(bus, UserCreated.type(), durable: "durable")
    assert_received {:signal, "durable", ^record}
    assert :ok = Bus.ack(bus, "durable", record.cursor)
    assert :ok = Bus.unsubscribe(bus, "durable")
    assert {:ok, "durable"} = Bus.subscribe(bus, UserCreated, durable: "durable")
    refute_received {:signal, "durable", _record}
    assert :ok = Bus.delete_subscription(bus, "durable")
    assert Process.alive?(bus)
  end

  test "cleans up module-path targets and preserves other subscribers" do
    for kind <- [:ephemeral, :durable] do
      bus = start_supervised!({Bus, name: unique_name("module_down")})
      target = spawn(fn -> receive do: (:stop -> :ok) end)
      on_exit(fn -> if Process.alive?(target), do: Process.exit(target, :kill) end)
      identity = if kind == :durable, do: [durable: "gone"], else: [subscription_id: "gone"]
      assert {:ok, "gone"} = Bus.subscribe(bus, UserCreated, [target: target] ++ identity)
      assert {:ok, "kept"} = Bus.subscribe(bus, UserCreated.type(), subscription_id: "kept")
      terminate_and_wait(bus, target)

      event = UserCreated.new!()
      assert {:ok, [record]} = Bus.publish(bus, [event])
      assert_received {:signal, ^event}
      refute_received {:signal, ^event}

      if kind == :durable do
        assert {:ok, "gone"} = Bus.subscribe(bus, UserCreated, durable: "gone")
        assert_received {:signal, "gone", ^record}
        assert :ok = Bus.ack(bus, "gone", record.cursor)
      else
        assert {:error, :subscription_not_found} = Bus.unsubscribe(bus, "gone")
      end

      assert Process.alive?(bus)
    end
  end
end
