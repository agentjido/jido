defmodule Jido.Signal.BusTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal
  alias Jido.Signal.Bus

  def handle_delivery(_event, _measurements, metadata, {bus, target}) do
    if self() == bus, do: send(target, {:delivered_to, metadata})
  end

  def handle_subscription_event(event, _measurements, metadata, {bus, target}) do
    if self() == bus, do: send(target, {:subscription_event, event, metadata})
  end

  defmodule FailingStore do
    def init(_opts), do: {:error, :unavailable}
  end

  defmodule InvalidInitStore do
    def init(_opts), do: :invalid
  end

  defmodule RaisingInitStore do
    def init(_opts), do: raise("store failed")
  end

  defmodule StartupStore do
    @behaviour Jido.Signal.Bus.Store

    @impl true
    def init(opts), do: {:ok, Map.new(opts)}

    @impl true
    def append(_records, state), do: {:ok, state}

    @impl true
    def read(_opts, state), do: Map.get(state, :records, {:ok, []})

    @impl true
    def latest_cursor(state), do: Map.get(state, :latest_cursor, {:ok, 0})

    @impl true
    def list_subscriptions(state), do: Map.get(state, :subscriptions, {:ok, []})

    @impl true
    def put_subscription(_subscription, state), do: {:ok, state}

    @impl true
    def delete_subscription(_id, state), do: {:ok, state}
  end

  defmodule ObservingStore do
    @behaviour Jido.Signal.Bus.Store

    alias Jido.Signal.Bus.Store.Memory

    @impl true
    def init(opts) do
      observer = Keyword.fetch!(opts, :observer)

      with {:ok, memory} <- Memory.init(Keyword.delete(opts, :observer)) do
        {:ok, %{memory: memory, observer: observer}}
      end
    end

    @impl true
    def append(records, state) do
      send(state.observer, {:stored_records, records})

      with {:ok, memory} <- Memory.append(records, state.memory) do
        {:ok, %{state | memory: memory}}
      end
    end

    @impl true
    def read(opts, state), do: Memory.read(opts, state.memory)

    @impl true
    def latest_cursor(state), do: Memory.latest_cursor(state.memory)

    @impl true
    def list_subscriptions(state), do: Memory.list_subscriptions(state.memory)

    @impl true
    def put_subscription(subscription, state) do
      with {:ok, memory} <- Memory.put_subscription(subscription, state.memory) do
        {:ok, %{state | memory: memory}}
      end
    end

    @impl true
    def delete_subscription(id, state) do
      with {:ok, memory} <- Memory.delete_subscription(id, state.memory) do
        {:ok, %{state | memory: memory}}
      end
    end
  end

  test "publishes in order and keeps a bounded replay log" do
    bus = start_bus(max_log_size: 2)

    signals = [signal("order.one"), signal("order.two"), signal("order.three")]
    assert {:ok, records} = Bus.publish(bus, signals)
    assert Enum.map(records, & &1.cursor) == [1, 2, 3]

    assert {:ok, replayed} = Bus.replay(bus, "order.**")
    assert Enum.map(replayed, & &1.signal.type) == ["order.two", "order.three"]
    assert Enum.map(replayed, & &1.cursor) == [2, 3]

    assert {:ok, [last]} = Bus.replay(bus, "order.**", after: 2, limit: 1)
    assert last.cursor == 3
  end

  test "rejects remote subscription targets without stopping the Bus" do
    bus = start_bus()
    target = remote_pid()
    assert node(target) != node()

    assert {:error, :invalid_target} = Bus.subscribe(bus, "**", target: target)
    assert {:error, :invalid_target} = Bus.subscribe(bus, "**", target: target, durable: "remote")
    assert {:error, :not_found} = Bus.whereis(target)
    assert {:ok, [_]} = Bus.publish(bus, [signal("still.alive")])
  end

  test "rejects newline characters in subscription and replay paths" do
    bus = start_bus()

    for path <- ["event\n", "a\n.b", "a.b\n"] do
      assert {:error, _} = Bus.subscribe(bus, path)
      assert {:error, _} = Bus.subscribe(bus, path, durable: "invalid-path")
      assert {:error, _} = Bus.replay(bus, path)
    end

    assert {:ok, [_]} = Bus.publish(bus, [signal("still.alive")])
  end

  test "rejects improper publication and Store record lists without stopping the Bus" do
    bus = start_bus()
    event = signal("valid.event")
    assert {:ok, _} = Bus.subscribe(bus, "**")
    assert {:error, :invalid_signals} = Bus.publish(bus, [event | :tail])
    refute_received {:signal, ^event}
    assert {:ok, [record]} = Bus.publish(bus, [event])
    assert record.cursor == 1
    assert_received {:signal, ^event}
    assert {:ok, [^record]} = Bus.replay(bus)

    stored = %{
      "format_version" => 1,
      "id" => record.id,
      "cursor" => record.cursor,
      "type" => record.type,
      "created_at" => DateTime.to_iso8601(record.created_at),
      "signal" => Signal.to_map(record.signal)
    }

    custom = start_bus(store: StartupStore, store_opts: [records: {:ok, [stored | :tail]}])
    assert {:error, :invalid_store_records} = Bus.replay(custom)
    assert {:ok, "malformed"} = Bus.subscribe(custom, "**", durable: "malformed")
    # Subscribe completes after the malformed Store read. No head record is sent.
    refute_received {:signal, "malformed", _}
    assert Process.alive?(custom)
  end

  test "rejects improper startup options with the public error" do
    assert {:error, {:invalid_options, message}} = Bus.start_link([{:name, "valid"} | :tail])
    assert is_binary(message)
    assert_raise ArgumentError, message, fn -> Bus.child_spec([{:name, "valid"} | :tail]) end

    assert {:error, {:invalid_options, _}} =
             Bus.start_link(name: "valid", store_opts: [{:max_records, 2} | :tail])

    assert {:error, {:invalid_options, _}} =
             Bus.start_link([
               {:name, "valid"},
               {:store_opts, []},
               {:store_opts, [{:max_records, 2} | :tail]}
             ])
  end

  test "keeps the Zoi default and last-value rule for startup Store options" do
    for options <- [[store_opts: nil], [store_opts: :ignored, store_opts: []]] do
      bus = start_bus(options)
      assert {:ok, [_]} = Bus.publish(bus, [signal("default.options")])
    end
  end

  test "rejects improper Store definitions before starting the Bus" do
    Process.flag(:trap_exit, true)

    definition = %{
      "format_version" => 1,
      "id" => "saved",
      "path" => "**",
      "cursor" => 0,
      "created_at" => "2026-01-01T00:00:00Z"
    }

    assert {:error, :invalid_store_subscriptions} =
             Bus.start_link(
               name: unique_name("invalid_definitions"),
               store: StartupStore,
               store_opts: [subscriptions: {:ok, [definition | :tail]}]
             )
  end

  test "keeps durable delivery and retention equal to live wildcard routing" do
    bus = start_bus(max_log_size: 1)
    assert {:ok, "ordinary"} = Bus.subscribe(bus, "**.a", subscription_id: "ordinary")
    assert {:ok, "durable"} = Bus.subscribe(bus, "**.a", durable: "durable")
    event = signal("**.x.a")

    assert {:ok, [record]} = Bus.publish(bus, [event])
    assert_received {:signal, ^event}
    assert_received {:signal, "durable", ^record}
    assert {:ok, [^record]} = Bus.replay(bus, "**.a")
    assert {:ok, [_]} = Bus.publish(bus, [signal("other.event")])
    assert {:ok, [^record]} = Bus.replay(bus)

    assert {:error, {:store_error, :append, {:store_full, ["durable"]}}} =
             Bus.publish(bus, [signal("**.other.a")])

    assert :ok = Bus.ack(bus, "durable", record.cursor)
    assert {:ok, [_]} = Bus.publish(bus, [signal("other.event")])
  end

  test "keeps publication and replay correct as the last subscriber is removed" do
    bus = start_bus(store: ObservingStore, store_opts: [observer: self()])
    first = signal("stored.first")
    assert {:ok, [one]} = Bus.publish(bus, [first])
    assert_received {:stored_records, [_]}
    refute_received {:signal, _}

    assert {:ok, "only"} = Bus.subscribe(bus, "stored.**", subscription_id: "only")
    second = signal("stored.second")
    assert {:ok, [two]} = Bus.publish(bus, [second])
    assert_received {:stored_records, [_]}
    assert_received {:signal, ^second}
    assert :ok = Bus.unsubscribe(bus, "only")

    third = signal("stored.third")
    assert {:ok, [three]} = Bus.publish(bus, [third])
    assert_received {:stored_records, [_]}
    refute_received {:signal, _}
    assert {:ok, [^one, ^two, ^three]} = Bus.replay(bus)
    assert [one.cursor, two.cursor, three.cursor] == [1, 2, 3]
  end

  test "keeps Router precedence through Bus delivery" do
    name = unique_name("ordered_bus")
    bus = start_supervised!({Bus, name: name})
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:jido, :signal, :bus, :deliver],
        &__MODULE__.handle_delivery/4,
        {bus, self()}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, "multi"} =
             Bus.subscribe(bus, "ordered.**", subscription_id: "multi")

    assert {:ok, "single"} =
             Bus.subscribe(bus, "ordered.*", subscription_id: "single")

    assert {:ok, "exact"} =
             Bus.subscribe(bus, "ordered.event", subscription_id: "exact")

    assert {:ok, "durable"} =
             Bus.subscribe(bus, "ordered.event", durable: "durable")

    event = signal("ordered.event")
    assert {:ok, [record]} = Bus.publish(bus, [event])

    deliveries =
      for _index <- 1..4 do
        assert_received {:delivered_to, metadata}
        metadata
      end

    assert Enum.map(deliveries, & &1.subscription_id) == ["exact", "durable", "single", "multi"]

    assert Enum.map(deliveries, & &1.subscription_path) ==
             ["ordered.event", "ordered.event", "ordered.*", "ordered.**"]

    assert Enum.map(deliveries, & &1.durable) == [false, true, false, false]
    assert Enum.at(deliveries, 1).cursor == record.cursor

    for metadata <- deliveries do
      assert metadata.signal_id == event.id
      assert metadata.signal_type == event.type
      assert metadata.bus_name == name
      if not metadata.durable, do: refute(Map.has_key?(metadata, :cursor))
    end

    refute_received {:delivered_to, _metadata}
  end

  test "stores a versioned canonical Signal map before delivery" do
    bus = start_bus(store: ObservingStore, store_opts: [observer: self()])
    assert {:ok, _id} = Bus.subscribe(bus, "stored.*")
    event = signal("stored.created")

    assert {:ok, [_record]} = Bus.publish(bus, [event])

    assert_received {:stored_records, [stored]}
    assert stored["format_version"] == 1
    assert stored["cursor"] == 1
    assert stored["signal"] == Signal.to_map(event)
    assert stored["signal"]["specversion"] == "1.0"
    assert_received {:signal, ^event}
  end

  test "rejects malformed Signal structs before Store access" do
    bus = start_bus(store: ObservingStore, store_opts: [observer: self()])

    malformed = %Signal{
      id: "invalid",
      source: "/test",
      type: "stored.invalid",
      extensions: :invalid
    }

    assert {:error, %Jido.Signal.Error.InvalidInputError{} = error} =
             Bus.publish(bus, [malformed])

    assert error.details.index == 0
    refute_received {:stored_records, _records}
    assert Process.alive?(bus)
    assert {:ok, []} = Bus.replay(bus, "**")
  end

  test "removes a normal subscription after its target exits" do
    bus = start_bus()
    client = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    assert {:ok, "short-lived"} =
             Bus.subscribe(bus, "short.*", subscription_id: "short-lived", target: client)

    terminate_and_wait(bus, client)

    assert {:ok, "short-lived"} =
             Bus.subscribe(bus, "short.*", subscription_id: "short-lived")
  end

  test "emits one detach event when an active subscription target is removed" do
    bus = start_bus()
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:jido, :signal, :bus, :subscription, :detached],
        &__MODULE__.handle_subscription_event/4,
        {bus, self()}
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    assert {:ok, "normal"} = Bus.subscribe(bus, "normal.*", subscription_id: "normal")
    assert :ok = Bus.unsubscribe(bus, "normal")
    assert_receive {:subscription_event, _event, %{subscription_id: "normal", durable: false}}

    target = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})
    assert {:ok, "down"} = Bus.subscribe(bus, "down.*", subscription_id: "down", target: target)
    terminate_and_wait(bus, target)
    assert_receive {:subscription_event, _event, %{subscription_id: "down", durable: false}}

    assert {:ok, "active"} = Bus.subscribe(bus, "active.*", durable: "active")
    assert :ok = Bus.delete_subscription(bus, "active")
    assert_receive {:subscription_event, _event, %{subscription_id: "active", durable: true}}

    assert {:ok, "detached"} = Bus.subscribe(bus, "detached.*", durable: "detached")
    assert :ok = Bus.unsubscribe(bus, "detached")
    assert_receive {:subscription_event, _event, %{subscription_id: "detached", durable: true}}

    assert :ok = Bus.unsubscribe(bus, "detached")
    refute_receive {:subscription_event, _event, %{subscription_id: "detached"}}
    assert :ok = Bus.delete_subscription(bus, "detached")
    refute_receive {:subscription_event, _event, %{subscription_id: "detached"}}
  end

  test "emits detach before attach when replacing a dead durable target" do
    bus = start_bus()
    old_target = spawn(fn -> receive do: (:stop -> :ok) end)
    replacement = spawn(fn -> receive do: (:stop -> :ok) end)
    handler_id = {__MODULE__, self(), make_ref()}

    on_exit(fn ->
      if Process.alive?(bus), do: :sys.resume(bus)
      :telemetry.detach(handler_id)
      if Process.alive?(old_target), do: Process.exit(old_target, :kill)
      if Process.alive?(replacement), do: Process.exit(replacement, :kill)
    end)

    assert {:ok, "replace"} =
             Bus.subscribe(bus, "replace.*", durable: "replace", target: old_target)

    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :signal, :bus, :subscription, :detached],
          [:jido, :signal, :bus, :subscription, :attached]
        ],
        &__MODULE__.handle_subscription_event/4,
        {bus, self()}
      )

    :ok = :sys.suspend(bus)
    call_ref = make_ref()

    send(
      bus,
      {:"$gen_call", {self(), call_ref},
       {:subscribe, "replace.*", [durable: "replace", target: replacement]}}
    )

    Process.exit(old_target, :kill)
    :ok = :sys.resume(bus)

    assert_receive {^call_ref, {:ok, "replace"}}

    assert_receive {:subscription_event, [:jido, :signal, :bus, :subscription, :detached],
                    %{subscription_id: "replace"}}

    assert_receive {:subscription_event, [:jido, :signal, :bus, :subscription, :attached],
                    %{subscription_id: "replace"}}

    refute_receive {:subscription_event, _event, %{subscription_id: "replace"}}
  end

  test "rejects self-subscription and ignores unrelated messages" do
    bus = start_bus()

    assert {:error, :target_is_bus} = Bus.subscribe(bus, "self.*", target: bus)
    send(bus, {:signal, signal("self.sent")})
    send(bus, :unrelated)

    assert %{subscriptions: subscriptions} = :sys.get_state(bus)
    assert subscriptions == %{}
    assert Process.alive?(bus)
  end

  test "redacts retained data from OTP status" do
    bus = start_bus()
    secret = "status-secret-#{System.unique_integer([:positive])}"
    assert {:ok, [_record]} = Bus.publish(bus, [signal("status.secret", %{token: secret})])

    status = :sys.get_status(bus)

    refute inspect(status, limit: :infinity, printable_limit: :infinity) =~ secret
    assert inspect(status) =~ "subscription_count"
  end

  test "fails startup when the selected Store cannot start" do
    Process.flag(:trap_exit, true)
    name = unique_name("failed_store")

    assert {:error, {:store_init_failed, :unavailable}} =
             Bus.start_link(name: name, store: FailingStore)
  end

  test "rejects invalid and failed Store initialization" do
    Process.flag(:trap_exit, true)

    assert {:error, {:store_init_failed, {:invalid_return, :invalid}}} =
             Bus.start_link(name: unique_name("invalid_store"), store: InvalidInitStore)

    assert {:error, {:store_init_failed, {:exception, %RuntimeError{message: "store failed"}}}} =
             Bus.start_link(name: unique_name("raising_store"), store: RaisingInitStore)
  end

  test "rejects invalid persisted Store state" do
    Process.flag(:trap_exit, true)

    assert {:error, {:store_init_failed, :list_subscriptions, {:invalid_return, :invalid}}} =
             Bus.start_link(
               name: unique_name("invalid_list_return"),
               store: StartupStore,
               store_opts: [subscriptions: :invalid]
             )

    assert {:error, :invalid_store_subscriptions} =
             Bus.start_link(
               name: unique_name("invalid_subscriptions"),
               store: StartupStore,
               store_opts: [subscriptions: {:ok, :invalid}]
             )

    assert {:error, :invalid_store_subscription} =
             Bus.start_link(
               name: unique_name("unsupported_subscription_version"),
               store: StartupStore,
               store_opts: [subscriptions: {:ok, [%{"format_version" => 2}]}]
             )

    assert {:error, :invalid_store_cursor} =
             Bus.start_link(
               name: unique_name("invalid_cursor"),
               store: StartupStore,
               store_opts: [latest_cursor: {:ok, :invalid}]
             )

    definition = %{
      "format_version" => 1,
      "id" => "ahead",
      "path" => "stored.*",
      "cursor" => 1,
      "created_at" => "2026-01-01T00:00:00Z"
    }

    assert {:error, :invalid_store_subscription_cursor} =
             Bus.start_link(
               name: unique_name("ahead_cursor"),
               store: StartupStore,
               store_opts: [subscriptions: {:ok, [definition]}]
             )
  end

  test "rejects unknown start options through the Zoi schema" do
    assert {:error, {:invalid_options, message}} =
             Bus.start_link(name: unique_name("invalid_options"), unexpected: true)

    assert message =~ "unrecognized key: unexpected"

    assert_raise ArgumentError, ~r/unrecognized key: unexpected/, fn ->
      Bus.child_spec(name: unique_name("invalid_child_spec"), unexpected: true)
    end
  end

  test "validates all startup boundaries" do
    for opts <- [
          [],
          [name: ""],
          [name: nil],
          [name: :bus, registry: nil],
          [name: :bus, store: nil],
          [name: :bus, max_log_size: 0],
          [name: :bus, store_opts: :invalid]
        ] do
      assert {:error, {:invalid_options, message}} = Bus.start_link(opts)
      assert is_binary(message)
    end
  end

  test "supports PID and explicit Registry lookup" do
    registry = __MODULE__.CustomRegistry
    start_supervised!({Registry, keys: :unique, name: registry})

    {:ok, bus} = Bus.start_link(name: :custom_bus, registry: registry)

    assert Bus.via_tuple({:custom_bus, registry}) ==
             {:via, Registry, {registry, "custom_bus"}}

    assert {:ok, ^bus} = Bus.whereis(bus)
    assert {:ok, ^bus} = Bus.whereis({:custom_bus, registry})

    assert {:ok, _id} = Bus.subscribe({:custom_bus, registry}, "custom.*")
    event = signal("custom.created")
    assert {:ok, [_record]} = Bus.publish({:custom_bus, registry}, [event])
    assert_received {:signal, ^event}

    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _reason}, 1_000
    assert {:error, :not_found} = Bus.whereis(dead)
    assert {:error, :not_found} = Bus.whereis(:missing, registry: __MODULE__.MissingRegistry)
  end

  test "handles empty, invalid, and missing publish targets" do
    assert {:ok, []} = Bus.publish(:not_started, [])
    assert {:error, :invalid_signals} = Bus.publish(:not_started, :invalid)
    assert {:error, :not_found} = Bus.publish(:not_started, [signal("missing.event")])
    assert {:error, :invalid_options} = Bus.subscribe(:not_started, "**", :invalid)
    assert {:error, :not_found} = Bus.subscribe(:not_started, "**")
    assert {:error, :not_found} = Bus.unsubscribe(:not_started, "missing")
    assert {:error, :not_found} = Bus.delete_subscription(:not_started, "missing")
    assert {:error, :not_found} = Bus.replay(:not_started)
    assert {:error, :not_found} = Bus.ack(:not_started, "missing", 1)
  end

  test "reports a server shutdown during a call as not found" do
    server = spawn(fn -> receive do: ({:"$gen_call", _from, _message} -> exit(:shutdown)) end)
    monitor = Process.monitor(server)
    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :kill) end)

    assert {:error, :not_found} = Bus.replay(server)

    assert_receive {:DOWN, ^monitor, :process, ^server, :shutdown}
  end

  test "reports a server shutdown tuple during a call as not found" do
    reason = {:shutdown, :maintenance}
    server = spawn(fn -> receive do: ({:"$gen_call", _from, _message} -> exit(reason)) end)
    monitor = Process.monitor(server)
    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :kill) end)

    assert {:error, :not_found} = Bus.replay(server)

    assert_receive {:DOWN, ^monitor, :process, ^server, ^reason}
  end

  test "reports a normal server exit during a call as not found" do
    server = spawn(fn -> receive do: ({:"$gen_call", _from, _message} -> exit(:normal)) end)
    monitor = Process.monitor(server)
    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :kill) end)

    assert {:error, :not_found} = Bus.replay(server)

    assert_receive {:DOWN, ^monitor, :process, ^server, :normal}
  end

  test "does not report a server timeout exit as a call timeout" do
    server = spawn(fn -> receive do: ({:"$gen_call", _from, _message} -> exit(:timeout)) end)
    monitor = Process.monitor(server)
    on_exit(fn -> if Process.alive?(server), do: Process.exit(server, :kill) end)

    assert {:timeout, {GenServer, :call, [^server, {:replay, "**", []}, :infinity]}} =
             catch_exit(Bus.replay(server))

    assert_receive {:DOWN, ^monitor, :process, ^server, :timeout}
  end

  test "rejects removed dispatch and persistent subscription options" do
    bus = start_bus()

    assert {:error, {:unsupported_option, :dispatch}} =
             Bus.subscribe(bus, "old.*", dispatch: {:pid, target: self()})

    assert {:error, {:unsupported_option, :persistent?}} =
             Bus.subscribe(bus, "old.*", persistent?: true)
  end

  defp start_bus(opts \\ []) do
    name = unique_name("bus")
    start_supervised!({Bus, Keyword.put(opts, :name, name)})
  end
end
