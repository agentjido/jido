defmodule Jido.Signal.Bus.SelectorLookupTest do
  use JidoSignalTest.Case, async: false

  alias Jido.Signal
  alias Jido.Signal.{Bus, Error, Router}

  test "normal observation misses do not construct routing errors" do
    bus = start_supervised!({Bus, name: unique_name("selector_lookup")})

    assert {:ok, _} =
             Bus.subscribe(bus, "inventory.*", selector: [source: "/east", subject: "sku-42"])

    Code.ensure_loaded!(Error)
    callback = {Error, :routing_error, 2}
    {:match_spec, previous_pattern} = :erlang.trace_info(callback, :match_spec)
    assert 1 = :erlang.trace_pattern(callback, true, [:local])
    assert 1 = :erlang.trace(bus, true, [:call])

    try do
      events = [
        Signal.new!("inventory.changed", %{}, source: "/west", subject: "sku-42"),
        Signal.new!("inventory.changed", %{}, source: "/east", subject: "sku-43"),
        Signal.new!("sensor.reading", %{}, source: "/east", subject: "sku-42")
      ]

      assert {:ok, records} = Bus.publish(bus, events)
      assert Enum.map(records, & &1.signal) == events
      trace_ref = :erlang.trace_delivered(bus)
      assert_receive {:trace_delivered, ^bus, ^trace_ref}, 1_000
      refute_received {:trace, ^bus, :call, {Error, :routing_error, _args}}
      refute_received {:signal, _}

      router = :sys.get_state(bus).router
      assert {:error, %Error.RoutingError{}} = Router.route(router, hd(events))
      assert {:ok, ^records} = Bus.replay(bus)
    after
      if Process.alive?(bus), do: :erlang.trace(bus, false, [:call])
      :erlang.trace_pattern(callback, previous_pattern, [:local])
    end
  end
end
