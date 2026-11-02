defmodule Jido.Signal.Bus.DurableSubscriptionTest do
  use JidoSignalTest.Case, async: true

  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal
  alias Jido.Signal.Router
  alias JidoSignalTest.Fixtures.Signals.UserCreated

  defmodule SharedStore do
    @behaviour Jido.Signal.Bus.Store

    alias Jido.Signal.Bus.Store.Memory

    @impl true
    def init(opts) do
      case Keyword.fetch(opts, :agent) do
        {:ok, agent} when is_pid(agent) -> {:ok, agent}
        _invalid -> {:error, :missing_agent}
      end
    end

    @impl true
    def append(records, agent), do: update(agent, &Memory.append(records, &1))

    @impl true
    def read(opts, agent), do: Agent.get(agent, &Memory.read(opts, &1))

    @impl true
    def latest_cursor(agent), do: Agent.get(agent, &Memory.latest_cursor/1)

    @impl true
    def list_subscriptions(agent), do: Agent.get(agent, &Memory.list_subscriptions/1)

    @impl true
    def put_subscription(subscription, agent) do
      update(agent, &Memory.put_subscription(subscription, &1))
    end

    @impl true
    def delete_subscription(id, agent) do
      update(agent, &Memory.delete_subscription(id, &1))
    end

    defp update(agent, function) do
      Agent.get_and_update(agent, fn state ->
        case function.(state) do
          {:ok, next_state} -> {{:ok, agent}, next_state}
          {:error, reason} -> {{:error, reason}, state}
        end
      end)
    end
  end

  defmodule ControlledStore do
    @behaviour Jido.Signal.Bus.Store

    alias Jido.Signal.Bus.Store.Memory

    def fail_next(agent, callback, reason) do
      Agent.update(agent, fn state ->
        %{state | failures: Map.put(state.failures, callback, reason)}
      end)
    end

    @impl true
    def init(opts) do
      case Keyword.fetch(opts, :agent) do
        {:ok, agent} when is_pid(agent) -> {:ok, agent}
        _invalid -> {:error, :missing_agent}
      end
    end

    @impl true
    def append(records, agent),
      do: write_operation(agent, :append, &Memory.append(records, &1))

    @impl true
    def read(opts, agent), do: read_operation(agent, :read, &Memory.read(opts, &1))

    @impl true
    def latest_cursor(agent),
      do: read_operation(agent, :latest_cursor, &Memory.latest_cursor/1)

    @impl true
    def list_subscriptions(agent),
      do: read_operation(agent, :list_subscriptions, &Memory.list_subscriptions/1)

    @impl true
    def put_subscription(subscription, agent),
      do: write_operation(agent, :put_subscription, &Memory.put_subscription(subscription, &1))

    @impl true
    def delete_subscription(id, agent),
      do: write_operation(agent, :delete_subscription, &Memory.delete_subscription(id, &1))

    defp read_operation(agent, callback, function) do
      Agent.get_and_update(agent, fn state ->
        case Map.pop(state.failures, callback) do
          {nil, failures} ->
            {function.(state.memory), %{state | failures: failures}}

          {reason, failures} ->
            {{:error, reason}, %{state | failures: failures}}
        end
      end)
    end

    defp write_operation(agent, callback, function) do
      Agent.get_and_update(agent, fn state ->
        case Map.pop(state.failures, callback) do
          {nil, failures} ->
            case function.(state.memory) do
              {:ok, memory} -> {{:ok, agent}, %{state | memory: memory, failures: failures}}
              {:error, reason} -> {{:error, reason}, %{state | failures: failures}}
            end

          {reason, failures} ->
            {{:error, reason}, %{state | failures: failures}}
        end
      end)
    end
  end

  def handle_bus_event(event, measurements, metadata, target) do
    send(target, {:bus_telemetry, event, measurements, metadata})
  end

  test "sends one durable record at a time and advances only its cursor" do
    bus = start_bus()
    assert {:ok, "orders-agent"} = Bus.subscribe(bus, "durable.*", durable: "orders-agent")

    first = signal("durable.first")
    second = signal("durable.second")
    assert {:ok, [first_record, second_record]} = Bus.publish(bus, [first, second])

    assert_received {:signal, "orders-agent", %RecordedSignal{} = delivered_first}
    assert delivered_first.cursor == first_record.cursor
    assert delivered_first.signal == first
    refute_received {:signal, "orders-agent", _record}

    assert {:error, {:unexpected_cursor, 1}} = Bus.ack(bus, "orders-agent", 2)
    assert :ok = Bus.ack(bus, "orders-agent", delivered_first.cursor)

    assert_received {:signal, "orders-agent", %RecordedSignal{} = delivered_second}
    assert delivered_second.cursor == second_record.cursor
    assert delivered_second.signal == second
    assert :ok = Bus.ack(bus, "orders-agent", delivered_second.cursor)
    refute_received {:signal, "orders-agent", _record}
  end

  test "sends an unacknowledged record again after a target exits" do
    bus = start_bus()
    parent = self()
    client = start_supervised!({Task, fn -> relay_durable(parent) end})

    assert {:ok, "offline-agent"} =
             Bus.subscribe(bus, "offline.*", durable: "offline-agent", target: client)

    event = signal("offline.created")
    assert {:ok, [published]} = Bus.publish(bus, [event])
    assert_receive {:relayed, "offline-agent", %RecordedSignal{} = first_delivery}, 1_000
    assert first_delivery.cursor == published.cursor

    terminate_and_wait(bus, client)

    assert {:ok, "offline-agent"} =
             Bus.subscribe(bus, "offline.*", durable: "offline-agent")

    assert_received {:signal, "offline-agent", %RecordedSignal{} = repeated}
    assert repeated.cursor == first_delivery.cursor
    assert repeated.signal == event
  end

  test "keeps records published while a durable subscription is detached" do
    bus = start_bus()

    assert {:ok, "detached-agent"} =
             Bus.subscribe(bus, "detached.*", durable: "detached-agent")

    assert :ok = Bus.unsubscribe(bus, "detached-agent")
    event = signal("detached.created")
    assert {:ok, [published]} = Bus.publish(bus, [event])
    refute_received {:signal, "detached-agent", _record}

    assert {:ok, "detached-agent"} =
             Bus.subscribe(bus, "detached.*", durable: "detached-agent")

    assert_received {:signal, "detached-agent", %RecordedSignal{} = delivered}
    assert delivered.cursor == published.cursor
    assert delivered.signal == event
  end

  test "rejects acknowledgement from a process that does not own the subscription" do
    bus = start_bus()
    parent = self()
    client = start_supervised!({Task, fn -> relay_durable(parent) end})

    assert {:ok, "owned-agent"} =
             Bus.subscribe(bus, "owned.*", durable: "owned-agent", target: client)

    assert {:ok, [published]} = Bus.publish(bus, [signal("owned.created")])
    assert_receive {:relayed, "owned-agent", %RecordedSignal{cursor: cursor}}, 1_000
    assert cursor == published.cursor
    assert {:error, :not_subscription_owner} = Bus.ack(bus, "owned-agent", cursor)
  end

  test "fails publish without delivery when a durable cursor fills the Store" do
    bus = start_bus(max_log_size: 2)

    assert {:ok, "pressure-agent"} =
             Bus.subscribe(bus, "pressure.*", durable: "pressure-agent", start_from: :origin)

    assert {:ok, _ephemeral} = Bus.subscribe(bus, "pressure.*")
    first = signal("pressure.first")
    second = signal("pressure.second")
    assert {:ok, [_first, _second]} = Bus.publish(bus, [first, second])

    assert_received {:signal, "pressure-agent", %RecordedSignal{cursor: 1}}
    assert_received {:signal, ^first}
    assert_received {:signal, ^second}

    third = signal("pressure.third")

    assert {:error, {:store_error, :append, {:store_full, ["pressure-agent"]}}} =
             Bus.publish(bus, [third])

    refute_received {:signal, ^third}
    assert {:ok, replayed} = Bus.replay(bus, "pressure.*")
    assert Enum.map(replayed, & &1.cursor) == [1, 2]
  end

  test "loads durable definitions and unacknowledged records from a custom Store" do
    {:ok, memory} = Jido.Signal.Bus.Store.Memory.init([])
    store_agent = start_supervised!({Agent, fn -> memory end})
    dynamic_supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})
    name = unique_name("shared_store")
    bus_opts = [name: name, store: SharedStore, store_opts: [agent: store_agent]]

    assert {:ok, bus} = DynamicSupervisor.start_child(dynamic_supervisor, {Bus, bus_opts})

    assert {:ok, "restart-agent"} =
             Bus.subscribe(bus, "restart.*", durable: "restart-agent")

    event = signal("restart.created")
    assert {:ok, [published]} = Bus.publish(bus, [event])
    assert_received {:signal, "restart-agent", %RecordedSignal{cursor: cursor}}
    assert cursor == published.cursor

    assert :ok = DynamicSupervisor.terminate_child(dynamic_supervisor, bus)

    assert {:ok, restarted_bus} =
             DynamicSupervisor.start_child(dynamic_supervisor, {Bus, bus_opts})

    assert {:ok, "restart-agent"} =
             Bus.subscribe(restarted_bus, "restart.*", durable: "restart-agent")

    assert_received {:signal, "restart-agent", %RecordedSignal{} = repeated}
    assert repeated.cursor == published.cursor
    assert repeated.signal == event
  end

  test "restores durable module paths in Store creation order" do
    {:ok, memory} = Jido.Signal.Bus.Store.Memory.init([])
    store_agent = start_supervised!({Agent, fn -> memory end})
    supervisor = start_supervised!({DynamicSupervisor, strategy: :one_for_one})

    opts = [
      name: unique_name("module_restore"),
      store: SharedStore,
      store_opts: [agent: store_agent]
    ]

    assert {:ok, bus} = DynamicSupervisor.start_child(supervisor, {Bus, opts})

    for id <- ["first", "middle", "last"] do
      assert {:ok, ^id} = Bus.subscribe(bus, UserCreated, durable: id)
    end

    event = UserCreated.new!()
    assert {:ok, [record]} = Bus.publish(bus, [event])
    for id <- ["first", "middle", "last"], do: assert_received({:signal, ^id, ^record})
    assert :ok = Bus.delete_subscription(bus, "middle")
    assert :ok = DynamicSupervisor.terminate_child(supervisor, bus)
    assert {:ok, restored} = DynamicSupervisor.start_child(supervisor, {Bus, opts})
    assert {:ok, ["first", "last"]} = Router.route(:sys.get_state(restored).router, event)

    for id <- ["last", "first"] do
      assert {:ok, ^id} = Bus.subscribe(restored, UserCreated.type(), durable: id)
      assert_received {:signal, ^id, ^record}
      assert :ok = Bus.ack(restored, id, record.cursor)
    end

    assert {:ok, ["first", "last"]} = Router.route(:sys.get_state(restored).router, event)
    assert {:ok, definitions} = SharedStore.list_subscriptions(store_agent)
    assert Enum.map(definitions, & &1["id"]) == ["first", "last"]
    assert Enum.all?(definitions, &(&1["path"] == UserCreated.type()))
  end

  test "keeps the stored creation timestamp unchanged after restore and acknowledgement" do
    for created_at <- [
          "2026-01-01T01:00:00+01:00",
          "2026-01-01T00:00:00+00:00",
          "2026-01-01T00:00:00.1234567Z",
          "2026-01-01T00:00:00Z"
        ] do
      definition = %{
        "format_version" => 1,
        "id" => "restored",
        "path" => "restore.*",
        "cursor" => 0,
        "created_at" => created_at
      }

      {:ok, memory} = Jido.Signal.Bus.Store.Memory.init([])
      {:ok, memory} = Jido.Signal.Bus.Store.Memory.put_subscription(definition, memory)
      store = start_supervised!({Agent, fn -> memory end}, id: {:timestamp_store, created_at})
      bus = start_bus(store: SharedStore, store_opts: [agent: store])
      assert {:ok, "restored"} = Bus.subscribe(bus, "restore.*", durable: "restored")

      for number <- 1..2 do
        assert {:ok, [record]} = Bus.publish(bus, [signal("restore.event")])
        assert_received {:signal, "restored", ^record}
        assert :ok = Bus.ack(bus, "restored", record.cursor)
        assert {:ok, [stored]} = SharedStore.list_subscriptions(store)
        assert stored["created_at"] == created_at
        assert stored["cursor"] == number
      end
    end
  end

  test "reports a Store read failure while attaching and remains usable" do
    {bus, store} = start_controlled_bus()
    attach_delivery_error_handler()
    ControlledStore.fail_next(store, :read, :temporarily_unavailable)

    assert {:ok, "attach-reader"} =
             Bus.subscribe(bus, "attach.*", durable: "attach-reader", start_from: :origin)

    assert_receive {:bus_telemetry, [:jido, :signal, :bus, :delivery_error], _measurements,
                    %{
                      subscription_id: "attach-reader",
                      reason: {:store_error, :read, :temporarily_unavailable}
                    }}

    event = signal("attach.created")
    assert {:ok, [_record]} = Bus.publish(bus, [event])

    assert_receive {:signal, "attach-reader", %RecordedSignal{signal: ^event}}
  end

  test "reports a Store read failure during publish and retries on later work" do
    {bus, store} = start_controlled_bus()
    attach_delivery_error_handler()

    assert {:ok, "publish-reader"} =
             Bus.subscribe(bus, "publish.*", durable: "publish-reader", start_from: :origin)

    ControlledStore.fail_next(store, :read, :temporarily_unavailable)
    first = signal("publish.first")
    assert {:ok, [_record]} = Bus.publish(bus, [first])
    refute_received {:signal, "publish-reader", _record}

    assert_receive {:bus_telemetry, [:jido, :signal, :bus, :delivery_error], _measurements,
                    %{
                      subscription_id: "publish-reader",
                      signal_id: signal_id,
                      signal_type: "publish.first",
                      reason: {:store_error, :read, :temporarily_unavailable}
                    }}

    assert signal_id == first.id

    assert {:ok, [_record]} = Bus.publish(bus, [signal("publish.second")])
    assert_receive {:signal, "publish-reader", %RecordedSignal{signal: ^first}}
  end

  test "keeps acknowledgement state safe across Store write and read failures" do
    {bus, store} = start_controlled_bus()
    attach_delivery_error_handler()

    assert {:ok, "ack-reader"} =
             Bus.subscribe(bus, "ack.*", durable: "ack-reader", start_from: :origin)

    first = signal("ack.first")
    second = signal("ack.second")
    assert {:ok, [_first_record, _second_record]} = Bus.publish(bus, [first, second])
    assert_receive {:signal, "ack-reader", %RecordedSignal{cursor: first_cursor, signal: ^first}}

    ControlledStore.fail_next(store, :put_subscription, :temporarily_unavailable)

    assert {:error, {:store_error, :put_subscription, :temporarily_unavailable}} =
             Bus.ack(bus, "ack-reader", first_cursor)

    ControlledStore.fail_next(store, :read, :temporarily_unavailable)
    assert :ok = Bus.ack(bus, "ack-reader", first_cursor)

    assert_receive {:bus_telemetry, [:jido, :signal, :bus, :delivery_error], _measurements,
                    %{
                      subscription_id: "ack-reader",
                      reason: {:store_error, :read, :temporarily_unavailable}
                    }}

    assert {:ok, [_record]} = Bus.publish(bus, [signal("ack.third")])
    assert_receive {:signal, "ack-reader", %RecordedSignal{signal: ^second}}
  end

  test "allows only one active target for a durable subscription" do
    bus = start_bus()
    other = start_supervised!({Task, fn -> receive do: (:stop -> :ok) end})

    assert {:ok, "single-owner"} = Bus.subscribe(bus, "owner.*", durable: "single-owner")

    assert {:error, :subscription_in_use} =
             Bus.subscribe(bus, "owner.*", durable: "single-owner", target: other)

    assert {:error, :durable_subscription_conflict} =
             Bus.subscribe(bus, "other.*", durable: "single-owner", target: other)
  end

  test "permanently deletes a durable subscription" do
    bus = start_bus()
    assert {:ok, "old-agent"} = Bus.subscribe(bus, "old.*", durable: "old-agent")
    assert :ok = Bus.delete_subscription(bus, "old-agent")

    assert {:ok, "old-agent"} =
             Bus.subscribe(bus, "new.*", durable: "old-agent", start_from: :origin)
  end

  test "keeps other durable routes after one subscription is deleted" do
    bus = start_bus()

    assert {:ok, "removed"} = Bus.subscribe(bus, "removed.*", durable: "removed")
    assert {:ok, "kept"} = Bus.subscribe(bus, "kept.*", durable: "kept")
    assert :ok = Bus.delete_subscription(bus, "removed")

    event = signal("kept.created")
    assert {:ok, [_record]} = Bus.publish(bus, [event])

    assert_receive {:signal, "kept", %RecordedSignal{signal: ^event}}
    refute_received {:signal, "removed", _record}
  end

  test "validates durable acknowledgement state" do
    bus = start_bus()

    assert {:error, :subscription_not_found} = Bus.ack(bus, "missing", 1)
    assert {:error, :invalid_cursor} = Bus.ack(bus, "missing", -1)

    assert {:ok, "normal"} =
             Bus.subscribe(bus, "normal.*", subscription_id: "normal")

    assert {:error, :subscription_not_durable} = Bus.ack(bus, "normal", 1)

    assert {:ok, "waiting"} = Bus.subscribe(bus, "waiting.*", durable: "waiting")
    assert {:error, :no_record_in_flight} = Bus.ack(bus, "waiting", 1)
  end

  test "validates durable start cursors" do
    bus = start_bus()

    assert {:ok, [_first, _second]} =
             Bus.publish(bus, [signal("cursor.first"), signal("cursor.second")])

    assert {:ok, "cursor-one"} =
             Bus.subscribe(bus, "cursor.*", durable: "cursor-one", start_from: 1)

    assert_received {:signal, "cursor-one", %RecordedSignal{cursor: 2}}

    assert {:error, {:invalid_option, :start_from}} =
             Bus.subscribe(bus, "cursor.*", durable: "future", start_from: 3)

    assert {:error, {:invalid_option, :start_from}} =
             Bus.subscribe(bus, "cursor.*", durable: "invalid", start_from: :invalid)
  end

  test "returns the existing durable subscription for the same target" do
    bus = start_bus()

    assert {:ok, "same"} = Bus.subscribe(bus, "same.*", durable: "same")
    assert {:ok, "same"} = Bus.subscribe(bus, "same.*", durable: "same")
  end

  test "rejects identity conflicts and invalid subscription options" do
    bus = start_bus()

    assert {:error, {:conflicting_options, [:durable, :subscription_id]}} =
             Bus.subscribe(bus, "**", durable: "one", subscription_id: "two")

    assert {:error, {:requires_option, :start_from, :durable}} =
             Bus.subscribe(bus, "**", start_from: :origin)

    assert {:error, {:invalid_option, :durable}} =
             Bus.subscribe(bus, "**", durable: "")

    assert {:error, {:invalid_option, :subscription_id}} =
             Bus.subscribe(bus, "**", subscription_id: "")

    assert {:error, {:invalid_option, :subscription_id}} =
             Bus.subscribe(bus, "**", subscription_id: nil)

    assert {:ok, "shared"} =
             Bus.subscribe(bus, "normal.*", subscription_id: "shared")

    assert {:error, :subscription_already_exists} =
             Bus.subscribe(bus, "durable.*", durable: "shared")
  end

  test "validates unsubscribe, delete, replay, and target inputs" do
    bus = start_bus()

    assert {:error, :subscription_not_found} = Bus.unsubscribe(bus, "missing")
    assert {:error, :invalid_options} = Bus.unsubscribe(bus, "missing", force: true)
    assert {:error, :subscription_not_found} = Bus.delete_subscription(bus, "missing")
    assert {:error, _reason} = Bus.subscribe(bus, "bad.***")
    assert {:error, :invalid_target} = Bus.subscribe(bus, "**", target: :not_a_pid)

    dead = spawn(fn -> :ok end)
    monitor = Process.monitor(dead)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _reason}, 1_000
    assert {:error, :target_not_alive} = Bus.subscribe(bus, "**", target: dead)

    assert {:error, :invalid_options} = Bus.replay(bus, "**", :invalid)
    assert {:error, :invalid_options} = Bus.replay(bus, "**", [1])
    assert {:error, :invalid_options} = Bus.subscribe(bus, "**", [1])
    assert {:error, :invalid_options} = Bus.unsubscribe(bus, "missing", [1])
    assert {:error, {:unsupported_option, :unknown}} = Bus.replay(bus, "**", unknown: true)
    assert {:error, {:invalid_option, :after}} = Bus.replay(bus, "**", after: -1)
    assert {:error, {:invalid_option, :limit}} = Bus.replay(bus, "**", limit: 0)
    assert {:error, _reason} = Bus.replay(bus, "bad.***")
  end

  test "removes an ephemeral subscription without changing other routes" do
    bus = start_bus()
    assert {:ok, "first"} = Bus.subscribe(bus, "kept.*", subscription_id: "first")
    assert {:ok, "second"} = Bus.subscribe(bus, "kept.*", subscription_id: "second")

    assert :ok = Bus.delete_subscription(bus, "first")
    event = signal("kept.event")
    assert {:ok, [_record]} = Bus.publish(bus, [event])
    assert_received {:signal, ^event}
    refute_received {:signal, ^event}
  end

  defp start_bus(opts \\ []) do
    name = unique_name("durable_bus")
    start_supervised!({Bus, Keyword.put(opts, :name, name)})
  end

  defp start_controlled_bus do
    {:ok, memory} = Jido.Signal.Bus.Store.Memory.init([])

    store =
      start_supervised!({Agent, fn -> %{memory: memory, failures: %{}} end})

    bus = start_bus(store: ControlledStore, store_opts: [agent: store])
    {bus, store}
  end

  defp attach_delivery_error_handler do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        handler_id,
        [:jido, :signal, :bus, :delivery_error],
        &__MODULE__.handle_bus_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  defp relay_durable(parent) do
    receive do
      {:signal, durable_id, record} ->
        send(parent, {:relayed, durable_id, record})
        relay_durable(parent)
    end
  end
end
