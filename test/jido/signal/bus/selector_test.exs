defmodule Jido.Signal.Bus.SelectorTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Router

  def handle_delivery(_event, _measurements, metadata, {bus, observer}) do
    if self() == bus, do: send(observer, {:delivered, metadata.subscription_id})
  end

  test "combines type matching with source, subject, or both" do
    events = [
      event("inventory.stock.changed", "/east", "sku-42"),
      event("inventory.stock.changed", "/west", "sku-42"),
      event("inventory.stock.changed", "/east", "sku-43"),
      event("inventory.stock.changed", "/east", nil),
      event("inventory.stock.changed", "/east", "sku-42"),
      event("sensor.reading", "/east", "sku-42")
    ]

    for path <- ["inventory.stock.changed", "inventory.*.changed", "inventory.**", "**.changed"],
        {selector, indices} <- [
          {[source: "/east"], [0, 2, 3, 4]},
          {[subject: "sku-42"], [0, 1, 4]},
          {[source: "/east", subject: "sku-42"], [0, 4]},
          {[subject: "sku-42", source: "/east"], [0, 4]}
        ] do
      bus = start_bus()
      assert {:ok, _} = Bus.subscribe(bus, path, selector: selector)
      assert {:ok, records} = Bus.publish(bus, events)
      assert Enum.map(records, & &1.signal) == events

      for index <- indices do
        assert_received {:signal, received}
        assert received == Enum.at(events, index)
      end

      refute_received {:signal, _}
    end
  end

  test "matches source and subject exactly without changing or inspecting other fields" do
    bus = start_bus()

    assert {:ok, _} =
             Bus.subscribe(bus, "sensor.*", selector: [source: "/plant/1", subject: "sensor-1"])

    first = Signal.new!("sensor.reading", false, source: "/plant/1", subject: "sensor-1")

    last =
      Signal.new!("sensor.reading", %{"source" => "/other", "subject" => "other"},
        source: "/plant/1",
        subject: "sensor-1",
        time: "2026-10-12T12:00:00Z",
        dataschema: "https://example.com/sensor/v1",
        extensions: %{"region" => "west"}
      )

    rejected = [
      %{first | source: "/Plant/1"},
      %{first | source: "/plant/1/"},
      %{first | subject: "Sensor-1"},
      %{first | subject: "sensor-10"},
      %{first | subject: "sensor-1/reading"},
      %{first | subject: nil},
      %{first | type: "inventory.updated"}
    ]

    assert {:ok, _} = Bus.publish(bus, [first] ++ rejected ++ [last])
    assert_received {:signal, received_first}
    assert received_first == first
    assert_received {:signal, received_last}
    assert received_last == last
    refute_received {:signal, _}
  end

  test "isolates two message observers and keeps selected publication order" do
    bus = start_bus()
    first_target = start_target(:room_a)
    second_target = start_target(:room_b)

    for {target, subject} <- [{first_target, "room-a"}, {second_target, "room-b"}] do
      assert {:ok, _} =
               Bus.subscribe(bus, "message.added",
                 target: target,
                 selector: [source: "/messages", subject: subject]
               )
    end

    first = event("message.added", "/messages", "room-a")
    second = event("message.added", "/messages", "room-b")
    last = event("message.added", "/messages", "room-a")
    other_source = event("message.added", "/other", "room-a")
    assert {:ok, _} = Bus.publish(bus, [first, second, other_source, last])

    for expected <- [first, last] do
      assert_receive {:observed, :room_a, received}, 1_000
      assert received == expected
    end

    assert_receive {:observed, :room_b, ^second}, 1_000
    barrier(first_target)
    barrier(second_target)
    refute_received {:observed, _, _}
  end

  test "rejects unsupported fields, callbacks, malformed selectors, and duplicate keys" do
    bus = start_bus()
    observer = self()

    callback = fn _ ->
      send(observer, :callback_called)
      true
    end

    before = :sys.get_state(bus)

    invalid = [
      nil,
      [],
      false,
      %{},
      %{:source => "/east"},
      callback,
      {__MODULE__, :predicate, []},
      ["/east"],
      [source: "/east", source: "/west"],
      [subject: "a", subject: "b"],
      [source: "/east", subject: "a", subject: "b"],
      [{:source, "/east"} | :improper],
      [type: "sensor.*"],
      [data: %{}],
      [id: "id"],
      [time: "now"],
      [extensions: %{}],
      [source: "/east", data: %{}],
      [subject: nil],
      [source: nil],
      [source: ""],
      [subject: ""],
      [source: :east],
      [subject: 1],
      [subject: callback],
      [source: "contains a space"],
      [source: <<255>>],
      [subject: <<255>>],
      [subject: "bad\nvalue"],
      [source: String.duplicate("s", 4_097)],
      [subject: String.duplicate("s", 4_097)]
    ]

    for selector <- invalid do
      assert {:error, {:invalid_selector, message}} = Bus.subscribe(bus, "**", selector: selector)
      assert is_binary(message)
      assert :sys.get_state(bus) == before
    end

    refute_received :callback_called
    assert {:ok, _} = Bus.publish(bus, [event("sensor.reading", "/east", "sensor-1")])
    refute_received {:signal, _}
  end

  test "accepts selected strings at the byte bound and Signal module type paths" do
    bus = start_bus()
    source = "/" <> String.duplicate("s", 4_095)
    subject = String.duplicate("s", 4_096)

    assert {:ok, _} =
             Bus.subscribe(bus, JidoSignalTest.Fixtures.Signals.UserCreated,
               selector: [source: source, subject: subject]
             )

    selected = event("user.created", source, subject)
    assert {:ok, _} = Bus.publish(bus, [selected])
    assert_received {:signal, ^selected}
    refute_received {:signal, _}
  end

  test "rejects repeated outer selector options without ignoring a condition or invalid value" do
    bus = start_bus()
    before = :sys.get_state(bus)

    for values <- [
          [[source: "/east"], [subject: "sku-42"]],
          [[subject: "sku-42"], [source: "/east"]],
          [[source: "/east"], [source: "/east"]],
          [[source: "/east"], nil],
          [nil, [source: "/east"]]
        ] do
      opts = Enum.map(values, &{:selector, &1})
      assert {:error, {:invalid_selector, message}} = Bus.subscribe(bus, "inventory.*", opts)
      assert message =~ "once"
      assert :sys.get_state(bus) == before
    end

    unwanted = event("inventory.changed", "/east", "unwanted")
    assert {:ok, _} = Bus.publish(bus, [unwanted])
    refute_received {:signal, _}
  end

  test "rejects selectors for new and reattached durable subscriptions and replay" do
    bus = start_bus()
    selector = [source: "/east", subject: "sku-42"]
    before = :sys.get_state(bus)

    assert {:error, {:conflicting_options, [:selector, :durable]}} =
             Bus.subscribe(bus, "**", selector: selector, durable: "new", start_from: :origin)

    assert :sys.get_state(bus) == before
    assert {:ok, "existing"} = Bus.subscribe(bus, "**", durable: "existing")
    assert :ok = Bus.unsubscribe(bus, "existing")
    before = :sys.get_state(bus)

    for selector <- [selector, nil, []] do
      assert {:error, {:conflicting_options, [:selector, :durable]}} =
               Bus.subscribe(bus, "**", selector: selector, durable: "existing")

      assert :sys.get_state(bus) == before
    end

    assert {:ok, "existing"} = Bus.subscribe(bus, "**", durable: "existing")
    unfiltered = event("sensor.reading", "/west", "sensor-1")
    assert {:ok, [record]} = Bus.publish(bus, [unfiltered])
    assert_received {:signal, "existing", ^record}
    assert :ok = Bus.ack(bus, "existing", record.cursor)
    assert {:error, {:unsupported_option, :selector}} = Bus.replay(bus, "**", selector: selector)
    assert {:ok, [^record]} = Bus.replay(bus)
  end

  test "Router preserves precedence and registration order after metadata filtering" do
    bus = start_bus()
    selected = event("sensor.reading", "/east", "sensor-1")
    selector = [source: "/east", subject: "sensor-1"]
    handler = unique_name("selector_order")

    :ok =
      :telemetry.attach(
        handler,
        [:jido, :signal, :bus, :deliver],
        &__MODULE__.handle_delivery/4,
        {bus, self()}
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    for {id, path, opts} <- [
          {"broad", "**", [selector: selector]},
          {"wildcard", "sensor.*", [selector: selector]},
          {"first", "sensor.reading", [selector: selector]},
          {"skipped", "sensor.reading", [selector: [source: "/west"]]},
          {"default", "sensor.reading", []},
          {"last", "sensor.reading", [selector: selector]}
        ] do
      assert {:ok, ^id} = Bus.subscribe(bus, path, [subscription_id: id] ++ opts)
    end

    expected = ["first", "default", "last", "wildcard", "broad"]
    assert {:ok, ^expected} = Router.route(:sys.get_state(bus).router, selected)
    assert {:ok, _} = Bus.publish(bus, [selected])

    for id <- expected do
      assert_received {:delivered, received}
      assert received == id
      assert_received {:signal, ^selected}
    end

    refute_received {:delivered, _}
    refute_received {:signal, _}
  end

  test "unsubscribe and deletion remove matching state and allow the ID to be reused" do
    for removal <- [:unsubscribe, :delete_subscription],
        path <- ["sensor.reading", "sensor.*", "sensor.**", "**.reading"] do
      bus = start_bus()
      first = event("sensor.reading", "/east", "sensor-1")
      second = event("sensor.reading", "/east", "sensor-2")

      assert {:ok, "removed"} =
               Bus.subscribe(bus, path,
                 subscription_id: "removed",
                 selector: [subject: "sensor-1"]
               )

      assert {:ok, "kept"} =
               Bus.subscribe(bus, path, subscription_id: "kept", selector: [subject: "sensor-2"])

      assert :ok = apply(Bus, removal, [bus, "removed"])
      state = :sys.get_state(bus)
      refute Map.has_key?(state.subscriptions, "removed")
      assert map_size(state.monitors) == 1
      assert {:error, _} = Router.route(state.router, first)
      assert {:ok, ["kept"]} = Router.route(state.router, second)

      assert {:ok, "removed"} =
               Bus.subscribe(bus, path,
                 subscription_id: "removed",
                 selector: [subject: "sensor-2"]
               )

      assert {:ok, ["kept", "removed"]} = Router.route(:sys.get_state(bus).router, second)
      assert {:ok, _} = Bus.publish(bus, [first, second])
      assert_received {:signal, ^second}
      assert_received {:signal, ^second}
      refute_received {:signal, _}
      assert :ok = Bus.delete_subscription(bus, "removed")
      assert :ok = Bus.delete_subscription(bus, "kept")
      assert :sys.get_state(bus).monitors == %{}
      assert Router.empty?(:sys.get_state(bus).router)
    end
  end

  test "target exit and duplicate IDs preserve the other subscriber's selector" do
    bus = start_bus()
    target = start_target(:gone)

    assert {:ok, "gone"} =
             Bus.subscribe(bus, "sensor.*",
               target: target,
               subscription_id: "gone",
               selector: [source: "/west"]
             )

    assert {:ok, "kept"} =
             Bus.subscribe(bus, "sensor.*", subscription_id: "kept", selector: [source: "/east"])

    before = :sys.get_state(bus)

    assert {:error, :subscription_already_exists} =
             Bus.subscribe(bus, "sensor.*", subscription_id: "kept", selector: [source: "/west"])

    assert :sys.get_state(bus) == before
    terminate_and_wait(bus, target)
    state = :sys.get_state(bus)
    refute Map.has_key?(state.subscriptions, "gone")
    assert map_size(state.monitors) == 1
    selected = event("sensor.reading", "/east", nil)
    assert {:ok, ["kept"]} = Router.route(state.router, selected)
    assert {:ok, _} = Bus.publish(bus, [event("sensor.reading", "/west", nil), selected])
    assert_received {:signal, ^selected}
    refute_received {:signal, _}
  end

  defp start_bus, do: start_supervised!({Bus, name: unique_name("selector")})
  defp event(type, source, subject), do: Signal.new!(type, %{}, source: source, subject: subject)

  defp start_target(tag) do
    observer = self()
    target = spawn(fn -> target_loop(observer, tag) end)
    on_exit(fn -> if Process.alive?(target), do: Process.exit(target, :kill) end)
    target
  end

  defp target_loop(observer, tag) do
    receive do
      {:signal, signal} ->
        send(observer, {:observed, tag, signal})
        target_loop(observer, tag)

      {:barrier, caller, ref} ->
        send(caller, {:barrier, ref})
        target_loop(observer, tag)
    end
  end

  defp barrier(target) do
    ref = make_ref()
    send(target, {:barrier, self(), ref})
    assert_receive {:barrier, ^ref}, 1_000
  end
end
