defmodule JidoTest.Contract.PluginBusTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.plugin.bus", async: false

  alias Jido.Agent.Error
  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Bus.Client
  alias Jido.Plugin.Bus.Client.Runtime
  alias Jido.Plugin.Bus.DSL
  alias Jido.Plugin.Bus.DSL.References
  alias Jido.Plugin.Bus.Manager
  alias Jido.Plugin.Init
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal
  alias JidoTest.Plugin.BusFixtures, as: F
  alias Spark.Dsl.{Extension, Section}

  defp plugin_init(jido, options, agent_server \\ self()) do
    %Init{
      agent_server: agent_server,
      agent_id: "bus-contract",
      module: Client,
      jido: jido,
      options: options
    }
  end

  defp start_agent(jido, module, prefix) do
    JidoTest.AgentServerAssertions.start_agent(jido, module, id: unique_id(prefix))
  end

  defp client_runtime(server) do
    JidoTest.AgentServerAssertions.plugin(server, Client).pid
  end

  defp recorded_signal(value \\ 1) do
    signal = signal("bus.input", %{value: value})

    %RecordedSignal{
      id: "record-#{value}",
      cursor: value,
      type: signal.type,
      created_at: DateTime.utc_now(),
      signal: signal
    }
  end

  @tag obligation: "jido.plugin.bus.I1"
  test "Bus declarations produce one named endpoint and stable references" do
    expected = %{buses: [%{name: :events}]}
    section = %{Extension.default_section_config() | opts: [name: :events]}
    dsl = %{[:signal_bus] => section}

    assert [%Section{name: :signal_bus, schema: schema}] = DSL.sections()
    assert schema == [name: [type: :atom, required: true]]
    assert {:ok, ^expected} = DSL.lower(dsl, %{})
    assert {:ok, ^expected} = DSL.lower(%{}, expected)
    assert {:error, %Error{code: :ambiguous_config}} = DSL.lower(dsl, expected)
    assert {:error, %Error{code: :bus_name}} = DSL.lower(%{}, %{})

    assert References.bus(:events) == %{kind: :bus, name: :events}
    assert DSL.authoring_imports() == [References]
    assert DSL.endpoint_kinds() == [:bus]
    assert {:ok, ^expected} = DSL.normalize(expected)
    assert DSL.endpoints(expected) == [%{kind: :bus, name: :events}]

    for buses <- [[], [%{name: :first}, %{name: :second}]] do
      assert {:error, %Error{code: :bus_count}} = DSL.normalize(%{buses: buses})
    end

    assert {:error, %Error{code: :bus_to_bus}} =
             DSL.verify_connection(expected, %{
               from: %{kind: :bus},
               to: %{kind: :bus},
               delivery: :single
             })

    assert {:error, %Error{code: :bus_delivery, path: [:delivery]}} =
             DSL.verify_connection(expected, %{
               from: %{kind: :agent},
               to: %{kind: :bus},
               delivery: :broadcast
             })

    assert :ok =
             DSL.verify_connection(expected, %{
               from: %{kind: :agent},
               to: %{kind: :bus},
               delivery: :single
             })

    assert :ok =
             DSL.verify_connection(expected, %{
               from: %{kind: :bus},
               to: %{kind: :agent},
               delivery: :single
             })

    assert :ok =
             DSL.verify_connection(expected, %{
               from: %{kind: :agent},
               to: %{kind: :agent},
               delivery: :broadcast
             })
  end

  @tag obligation: "jido.plugin.bus.I2"
  test "Manager applies ownership defaults and stops its Bus with the Agent", %{jido: jido} do
    {:ok, agent} = start_agent(jido, F.ManagerAgent, "managed-bus")
    agent_id = Server.agent(agent).id

    assert {:ok, bus} = Bus.whereis(agent_id, jido: jido)
    assert JidoTest.AgentServerAssertions.plugin(agent, Manager).pid == bus

    assert :ok = Jido.stop_agent(jido, agent)
    eventually(fn -> Bus.whereis(agent_id, jido: jido) == {:error, :not_found} end)

    init = %Init{
      agent_server: self(),
      agent_id: "default-name",
      module: Manager,
      jido: jido,
      options: []
    }

    spec = Manager.child_spec(init)
    assert spec.id == Manager
    assert Map.get(spec, :restart, :permanent) == :permanent
    assert {Bus, :start_link, [options]} = spec.start
    assert options[:name] == "default-name"
    assert options[:jido] == jido

    explicit = %{init | options: [name: :shared, jido: nil, max_log_size: 5]}
    assert {Bus, :start_link, [options]} = Manager.child_spec(explicit).start
    assert options[:name] == :shared
    assert options[:jido] == nil
    assert options[:max_log_size] == 5
  end

  @tag obligation: "jido.plugin.bus.I3"
  test "Client applies defaults and rejects each invalid owned option", %{jido: jido} do
    bus = start_supervised!({Bus, name: :client_config_bus, jido: jido})
    init = plugin_init(jido, bus: :client_config_bus)
    client = start_supervised!({Runtime, init})

    assert :ok = Client.Server.await_ready(client, [])

    assert %{
             bus: :client_config_bus,
             durable: nil,
             lookup_opts: [jido: ^jido],
             path: "**",
             retry_delay_ms: 1_000,
             start_from: nil,
             timeout: 5_000
           } = :sys.get_state(client).config

    assert :ok = Runtime.terminate(:normal, :sys.get_state(client))
    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{})])
    refute_receive {:"$gen_cast", {:turn, _token, _signal, _context, _timeout}}, 50

    boundary_init = plugin_init(jido, bus: :input, retry_delay_ms: 1, timeout: 1)
    task = Task.async(fn -> Runtime.init(boundary_init) end)
    assert {:ok, boundary, {:continue, :subscribe}} = Task.await(task)
    assert boundary.config.retry_delay_ms == 1
    assert boundary.config.timeout == 1
    assert :ok = Runtime.terminate(:normal, boundary)

    invalid = [
      {[], {:missing_bus_option, :bus}},
      {[bus: :input, path: ""], {:invalid_bus_path, ""}},
      {[bus: :input, path: :all], {:invalid_bus_path, :all}},
      {[bus: :input, durable: ""], {:invalid_durable_id, ""}},
      {[bus: :input, durable: :consumer], {:invalid_durable_id, :consumer}},
      {[bus: :input, start_from: :origin], {:requires_option, :start_from, :durable}},
      {[bus: :input, retry_delay_ms: 0], {:invalid_retry_delay, 0}},
      {[bus: :input, retry_delay_ms: :soon], {:invalid_retry_delay, :soon}},
      {[bus: :input, timeout: 0], {:invalid_timeout, 0}},
      {[bus: :input, timeout: :infinity], {:invalid_timeout, :infinity}}
    ]

    for {options, reason} <- invalid do
      assert {:error, ^reason} = Runtime.start_link(plugin_init(jido, options))
    end
  end

  @tag obligation: "jido.plugin.bus.I3"
  test "initial subscription fails when the selected Bus is absent", %{jido: jido} do
    init = plugin_init(jido, bus: :missing_bus)

    task = Task.async(fn -> Runtime.init(init) end)
    assert {:ok, state, {:continue, :subscribe}} = Task.await(task)

    assert {:stop, {:bus_subscription_failed, :not_found}, ^state} =
             Runtime.handle_continue(:subscribe, state)

    assert :ok = Runtime.terminate(:normal, state)
  end

  @tag obligation: "jido.plugin.bus.I4"
  test "readiness reconnects to a replacement and ignores stale work", %{jido: jido} do
    bus = start_supervised!({Bus, name: :replacement_bus, jido: jido}, id: :replacement_bus)

    client =
      start_supervised!(
        {Runtime, plugin_init(jido, bus: :replacement_bus, retry_delay_ms: 60_000)}
      )

    assert :ok = Client.Server.await_ready(client, [])

    state = :sys.get_state(client)
    old_bus = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> if Process.alive?(old_bus), do: Process.exit(old_bus, :kill) end)
    old_connection = %{bus: old_bus, id: "old", ref: make_ref()}

    assert {:reply, :ok, refreshed} =
             Runtime.handle_call(:await_ready, self(), %{state | connection: old_connection})

    assert refreshed.connection.bus == bus
    assert refreshed.connection.id != "old"
    assert :ok = Runtime.terminate(:normal, refreshed)
    Process.demonitor(refreshed.connection.ref, [:flush])

    invalid = put_in(state.config.path, "bad.***")

    assert {:reply, {:error, :not_ready}, retrying} =
             Runtime.handle_call(:await_ready, self(), %{
               invalid
               | connection: old_connection,
                 reconnect_token: nil
             })

    assert retrying.connection == nil
    assert is_reference(retrying.reconnect_token)

    monitor = Process.monitor(bus)
    assert :ok = stop_supervised(:replacement_bus)
    assert_receive {:DOWN, ^monitor, :process, ^bus, :shutdown}

    old_token =
      eventually(fn ->
        case :sys.get_state(client) do
          %{connection: nil, reconnect_token: token} when is_reference(token) -> token
          _state -> nil
        end
      end)

    assert {:error, :not_ready} = Client.Server.await_ready(client, [])

    send(client, {:reconnect, old_token})
    failed = :sys.get_state(client)
    next_token = failed.reconnect_token
    assert is_reference(next_token)
    refute next_token == old_token

    replacement =
      start_supervised!({Bus, name: :replacement_bus, jido: jido}, id: :replacement_bus)

    send(client, {:reconnect, next_token})

    connected = :sys.get_state(client)
    assert connected.connection.bus == replacement
    assert is_binary(connected.connection.id)
    assert connected.reconnect_token == nil

    send(client, {:reconnect, old_token})
    send(client, {:reconnect, next_token})
    assert :sys.get_state(client) == connected

    assert :ok = stop_supervised(Runtime)

    assert {:error, {:bus_client_runtime_unavailable, _reason}} =
             Client.Server.await_ready(client, timeout: 10)
  end

  @tag obligation: ["jido.plugin.bus.I4", "jido.plugin.bus.I6", "jido.plugin.bus.I8"]
  test "Client ignores foreign lifecycle and durable delivery messages", %{jido: jido} do
    bus = start_supervised!({Bus, name: :message_filter_bus, jido: jido})
    client = start_supervised!({Runtime, plugin_init(jido, bus: :message_filter_bus)})
    state = :sys.get_state(client)
    connection = state.connection
    other = spawn(fn -> Process.sleep(:infinity) end)
    worker = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> if Process.alive?(other), do: Process.exit(other, :kill) end)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)

    wrong_ref = {:DOWN, make_ref(), :process, bus, :shutdown}
    wrong_bus = {:DOWN, connection.ref, :process, other, :shutdown}
    assert {:noreply, ^state} = Runtime.handle_info(wrong_ref, state)
    assert {:noreply, ^state} = Runtime.handle_info(wrong_bus, state)

    record = recorded_signal()
    assert {:noreply, ^state} = Runtime.handle_info({:signal, "other", record}, state)

    busy = %{state | pending: %{stage: :ack, token: make_ref(), record: record}}

    assert {:noreply, ^busy} =
             Runtime.handle_info({:signal, connection.id, record}, busy)

    ack_pending = %{busy | pending: Map.put(busy.pending, :worker, worker)}
    assert {:noreply, ^ack_pending} = Runtime.handle_info({:EXIT, worker, :killed}, ack_pending)

    delivery_pending = %{
      state
      | pending: %{stage: :deliver, token: make_ref(), record: record, worker: worker}
    }

    assert {:noreply, ^delivery_pending} =
             Runtime.handle_info({:EXIT, other, :killed}, delivery_pending)
  end

  @tag obligation: "jido.plugin.bus.I4"
  test "Client reconnect timer attaches to a replacement Bus", %{jido: jido} do
    bus = start_supervised!({Bus, name: :automatic_bus, jido: jido}, id: :automatic_bus)

    client =
      start_supervised!({Runtime, plugin_init(jido, bus: :automatic_bus, retry_delay_ms: 10)})

    assert :ok = Client.Server.await_ready(client, [])
    monitor = Process.monitor(bus)
    assert :ok = stop_supervised(:automatic_bus)
    assert_receive {:DOWN, ^monitor, :process, ^bus, :shutdown}
    replacement = start_supervised!({Bus, name: :automatic_bus, jido: jido}, id: :automatic_bus)

    eventually(fn ->
      match?(%{connection: %{bus: ^replacement}}, :sys.get_state(client))
    end)
  end

  @tag obligation: ["jido.plugin.bus.I2", "jido.plugin.bus.I5"]
  test "one Agent can own a Bus and consume normal Signals from it", %{jido: jido} do
    {:ok, agent} = start_agent(jido, F.OwnedBusAgent, "owned-bus")
    bus = JidoTest.AgentServerAssertions.plugin(agent, Manager).pid

    assert {:ok, ^bus} = Bus.whereis(:owned_plugin_bus, jido: jido)
    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 11})])
    eventually(fn -> Server.agent(agent).state.values == [11] end)
  end

  @tag obligation: "jido.plugin.bus.I5"
  test "Client casts normal subscribed Signals to its AgentServer", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = start_agent(jido, F.ClientAgent, "bus-client")

    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 1})])
    eventually(fn -> Server.agent(agent).state.values == [1] end)
  end

  @tag obligation: "jido.plugin.bus.I6"
  test "durable delivery waits for each committed Turn before it advances", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = start_agent(jido, F.DurableBlockingAgent, "durable-order")
    first_gate = make_ref()
    second_gate = make_ref()

    assert {:ok, [_first, _second]} =
             Bus.publish(bus, [
               signal("bus.block", %{value: 1, observer: self(), gate: first_gate}),
               signal("bus.block", %{value: 2, observer: self(), gate: second_gate})
             ])

    assert_receive {:bus_turn_blocked, 1, first_action}, 2_000
    refute_receive {:bus_turn_blocked, 2, _action}, 50
    assert Server.agent(agent).state.values == []

    send(first_action, {:release, first_gate})
    assert_receive {:bus_turn_blocked, 2, second_action}, 2_000
    assert Server.agent(agent).state.values == [1]

    send(second_action, {:release, second_gate})
    eventually(fn -> Server.agent(agent).state.values == [1, 2] end)
  end

  @tag obligation: "jido.plugin.bus.I7"
  test "durable delivery retries a failed Agent Turn", %{jido: jido} do
    table = :ets.new(:jido_bus_plugin_attempts, [:named_table, :public])
    :ets.insert(table, {:attempt, 0})

    on_exit(fn ->
      if :ets.whereis(:jido_bus_plugin_attempts) != :undefined, do: :ets.delete(table)
    end)

    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = start_agent(jido, F.DurableAgent, "durable-retry")

    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.retry", %{value: 9})])
    eventually(fn -> Server.agent(agent).state.values == [9] end)
    assert :ets.lookup_element(table, :attempt, 2) == 2
  end

  @tag obligation: "jido.plugin.bus.I7"
  test "durable acknowledgement retries and stale retry work stays inert" do
    ack_bus = start_supervised!({F.AckBus, {self(), [{:error, :store_down}, :ok]}})
    record = recorded_signal()

    worker = spawn(fn -> Process.sleep(:infinity) end)
    worker_ref = Process.monitor(worker)
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    token = make_ref()

    state = %{
      config: %{retry_delay_ms: 60_000},
      connection: %{bus: ack_bus, id: "durable-client"},
      pending: %{
        record: record,
        stage: :deliver,
        token: token,
        worker: worker,
        worker_ref: worker_ref
      },
      retry_timer: nil
    }

    stale_delivery = {:delivery_result, make_ref(), {:ok, %{}, []}}
    assert {:noreply, ^state} = Runtime.handle_info(stale_delivery, state)
    refute_received {:bus_ack, _durable_id, _cursor, _reply}

    assert {:noreply, retrying} =
             Runtime.handle_info({:delivery_result, token, {:ok, %{}, []}}, state)

    assert_receive {:bus_ack, "durable-client", 1, {:error, :store_down}}
    assert %{stage: :ack, record: ^record, token: retry_token} = retrying.pending
    assert is_reference(retrying.retry_timer)

    assert {:noreply, ^retrying} =
             Runtime.handle_info(
               {:delivery_result, retry_token, {:ok, %{}, []}},
               retrying
             )

    assert {:noreply, ^retrying} =
             Runtime.handle_info({:retry_record, make_ref()}, retrying)

    assert Process.cancel_timer(retrying.retry_timer)

    assert {:noreply, complete} =
             Runtime.handle_info({:retry_record, retry_token}, retrying)

    assert_receive {:bus_ack, "durable-client", 1, :ok}
    assert complete.pending == nil
    assert complete.retry_timer == nil
    assert {:noreply, ^complete} = Runtime.handle_info({:retry_record, retry_token}, complete)
  end

  @tag obligation: "jido.plugin.bus.I7"
  test "durable subscription reattaches after Client runtime replacement", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 3})])
    {:ok, agent} = start_agent(jido, F.DurableAgent, "durable-reattach")
    eventually(fn -> Server.agent(agent).state.values == [3] end)

    runtime = client_runtime(agent)
    root = Server.activation(agent)
    Process.exit(runtime, :kill)
    agent = JidoTest.AgentServerAssertions.replacement(root, agent)

    replacement =
      eventually(fn ->
        case client_runtime(agent) do
          pid when is_pid(pid) and pid != runtime -> pid
          _pid -> nil
        end
      end)

    assert Process.alive?(replacement)
    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 4})])
    eventually(fn -> Server.agent(agent).state.values == [3, 4] end)
  end

  @tag obligation: "jido.plugin.bus.I8"
  test "Bus loss stops its pending delivery worker", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido}, id: :pending_bus)
    {:ok, agent} = start_agent(jido, F.DurableBlockingAgent, "durable-bus-loss")
    runtime = client_runtime(agent)
    gate = make_ref()

    assert {:ok, [_record]} =
             Bus.publish(bus, [signal("bus.block", %{value: 1, observer: self(), gate: gate})])

    assert_receive {:bus_turn_blocked, 1, action}, 2_000
    delivery = :sys.get_state(runtime).pending.worker
    delivery_ref = Process.monitor(delivery)
    monitor = Process.monitor(bus)
    assert :ok = stop_supervised(:pending_bus)
    assert_receive {:DOWN, ^monitor, :process, ^bus, :shutdown}, 2_000
    assert_receive {:DOWN, ^delivery_ref, :process, ^delivery, _reason}, 2_000

    eventually(fn ->
      match?(%{connection: nil, pending: nil}, :sys.get_state(runtime))
    end)

    action_ref = Process.monitor(action)
    assert :ok = Jido.stop_agent(jido, agent)
    assert_receive {:DOWN, ^action_ref, :process, ^action, _reason}, 2_000
  end

  @tag obligation: "jido.plugin.bus.I8"
  test "delivery-worker failure retries without stopping the Client runtime", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = start_agent(jido, F.DurableBlockingAgent, "durable-worker")
    runtime = client_runtime(agent)
    gate = make_ref()

    assert {:ok, [_record]} =
             Bus.publish(bus, [signal("bus.block", %{value: 1, observer: self(), gate: gate})])

    assert_receive {:bus_turn_blocked, 1, action}, 2_000
    delivery = :sys.get_state(runtime).pending.worker
    delivery_ref = Process.monitor(delivery)
    Process.exit(delivery, :kill)
    assert_receive {:DOWN, ^delivery_ref, :process, ^delivery, :killed}, 2_000

    eventually(fn ->
      case :sys.get_state(runtime).pending do
        %{worker: replacement} -> replacement != delivery
        _pending -> false
      end
    end)

    assert :ok = Client.Server.await_ready(runtime, [])
    action_ref = Process.monitor(action)
    assert :ok = Jido.stop_agent(jido, agent)
    assert_receive {:DOWN, ^action_ref, :process, ^action, _reason}, 2_000
  end

  @tag obligation: "jido.plugin.bus.I8"
  test "Client runtime death stops its pending delivery worker", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = start_agent(jido, F.DurableBlockingAgent, "durable-owner")
    runtime = client_runtime(agent)
    gate = make_ref()

    assert {:ok, [_record]} =
             Bus.publish(bus, [signal("bus.block", %{value: 1, observer: self(), gate: gate})])

    assert_receive {:bus_turn_blocked, 1, action}, 2_000
    delivery = :sys.get_state(runtime).pending.worker
    delivery_ref = Process.monitor(delivery)
    runtime_ref = Process.monitor(runtime)

    root = Server.activation(agent)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :killed}, 2_000
    assert_receive {:DOWN, ^delivery_ref, :process, ^delivery, _reason}, 2_000

    agent = JidoTest.AgentServerAssertions.replacement(root, agent)
    action_ref = Process.monitor(action)
    assert :ok = Jido.stop_agent(jido, agent)
    assert_receive {:DOWN, ^action_ref, :process, ^action, _reason}, 2_000
  end
end
