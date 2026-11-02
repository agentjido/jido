defmodule Jido.Signal.Bus.SubscriptionRemovalTest do
  use JidoSignalTest.Case, async: true
  alias Jido.Signal.{Bus, Router}

  test "removes only the selected shared route and preserves registration order" do
    event = signal("bench.item.created")
    ids = ["first", "middle", "last"]

    for kind <- [:ephemeral, :durable],
        path <- ["bench.item.created", "bench.*.created", "bench.**.created", "**.created"],
        removed <- ids do
      bus = start_supervised!({Bus, name: unique_name("remove")})
      for id <- ids, do: subscribe(bus, path, kind, id)
      assert :ok = Bus.delete_subscription(bus, removed)
      remaining = Enum.reject(ids, &(&1 == removed))
      state = :sys.get_state(bus)
      assert map_size(state.monitors) == 2
      assert {:ok, ^remaining} = Router.route(state.router, event)

      subscribe(bus, path, kind, removed)
      expected = remaining ++ [removed]
      assert {:ok, ^expected} = Router.route(:sys.get_state(bus).router, event)
      assert {:ok, [record]} = Bus.publish(bus, [event])

      for id <- expected do
        if kind == :durable do
          assert_received {:signal, ^id, ^record}
          assert :ok = Bus.ack(bus, id, record.cursor)
        else
          assert_received {:signal, ^event}
        end
      end

      refute_received {:signal, _}
      refute_received {:signal, _, _}
      for id <- expected, do: assert(:ok == Bus.delete_subscription(bus, id))
      state = :sys.get_state(bus)
      assert state.monitors == %{}
      assert Router.empty?(state.router)
      refute Router.has_route?(state.router, path)
      subscribe(bus, path, kind, "new")
      assert {:ok, ["new"]} = Router.route(:sys.get_state(bus).router, event)
    end
  end

  test "target exit removes its shared route and leaves the other subscriber active" do
    bus = start_supervised!({Bus, name: unique_name("down")})
    target = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> if Process.alive?(target), do: Process.exit(target, :kill) end)
    assert {:ok, "gone"} = Bus.subscribe(bus, "bench.**", subscription_id: "gone", target: target)
    subscribe(bus, "bench.**", :ephemeral, "kept")
    terminate_and_wait(bus, target)
    event = signal("bench.created")
    assert {:ok, ["kept"]} = Router.route(:sys.get_state(bus).router, event)
    assert {:ok, [_]} = Bus.publish(bus, [event])
    assert_received {:signal, ^event}
    refute_received {:signal, ^event}
  end

  defp subscribe(bus, path, :ephemeral, id) do
    assert {:ok, ^id} = Bus.subscribe(bus, path, subscription_id: id)
  end

  defp subscribe(bus, path, :durable, id) do
    assert {:ok, ^id} = Bus.subscribe(bus, path, durable: id)
  end
end
