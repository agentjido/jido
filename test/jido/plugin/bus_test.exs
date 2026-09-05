defmodule Jido.Plugin.BusTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.Bus.{Client, Manager}
  alias Jido.Signal.Bus

  defmodule RecordAction do
    use Jido.Action, name: "bus_plugin_record"

    @impl Jido.Action
    def run(%{value: value}, context) do
      {:ok, %{context.agent_state | values: context.agent_state.values ++ [value]}}
    end
  end

  defmodule RetryAction do
    use Jido.Action, name: "bus_plugin_retry"

    @impl Jido.Action
    def run(%{value: value}, context) do
      attempt = :ets.update_counter(:jido_bus_plugin_attempts, :attempt, 1)

      if attempt == 1 do
        {:error, :simulated_failure}
      else
        {:ok, %{context.agent_state | values: context.agent_state.values ++ [value]}}
      end
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "bus_plugin_agent",
      schema: Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])}),
      routes: [{"bus.input", RecordAction}],
      plugins: [{Client, bus: :plugin_bus, path: "bus.**"}]
  end

  defmodule DurableAgent do
    use Jido.Agent,
      name: "durable_bus_plugin_agent",
      schema: Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])}),
      routes: [
        {"bus.input", RecordAction},
        {"bus.retry", RetryAction}
      ],
      plugins: [
        {Client,
         bus: :plugin_bus,
         path: "bus.**",
         durable: "durable-bus-agent",
         start_from: :origin,
         retry_delay_ms: 10}
      ]
  end

  defmodule ManagerAgent do
    use Jido.Agent,
      name: "bus_manager_agent",
      plugins: [Manager]
  end

  defmodule OwnedBusAgent do
    use Jido.Agent,
      name: "owned_bus_agent",
      schema: Zoi.object(%{values: Zoi.list(Zoi.integer()) |> Zoi.default([])}),
      routes: [{"bus.input", RecordAction}],
      plugins: [
        {Manager, name: :owned_plugin_bus},
        {Client, bus: :owned_plugin_bus, path: "bus.**", retry_delay_ms: 10}
      ]
  end

  test "casts normal Bus input into the Agent", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = Jido.start_agent(jido, Agent, id: unique_id("bus"))

    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 1})])
    eventually(fn -> Server.agent(agent).state.values == [1] end)
  end

  test "acknowledges durable input only after ordered Agent commits", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = Jido.start_agent(jido, DurableAgent, id: unique_id("durable-bus"))

    assert {:ok, [_first, _second]} =
             Bus.publish(bus, [
               signal("bus.input", %{value: 1}),
               signal("bus.input", %{value: 2})
             ])

    eventually(fn -> Server.agent(agent).state.values == [1, 2] end)
  end

  test "reattaches a durable subscription after its runtime restarts", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = Jido.start_agent(jido, DurableAgent, id: unique_id("durable-restart"))
    runtime = Server.children(agent)[{:plugin, Client}].pid

    Process.exit(runtime, :kill)

    new_runtime =
      eventually(fn ->
        case Server.children(agent)[{:plugin, Client}].pid do
          pid when is_pid(pid) and pid != runtime -> pid
          _other -> nil
        end
      end)

    assert Process.alive?(new_runtime)
    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 3})])
    eventually(fn -> Server.agent(agent).state.values == [3] end)
  end

  test "retries durable input after an Agent turn fails", %{jido: jido} do
    table = :ets.new(:jido_bus_plugin_attempts, [:named_table, :public])
    :ets.insert(table, {:attempt, 0})

    on_exit(fn ->
      if :ets.whereis(:jido_bus_plugin_attempts) != :undefined, do: :ets.delete(table)
    end)

    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido})
    {:ok, agent} = Jido.start_agent(jido, DurableAgent, id: unique_id("durable-retry"))

    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.retry", %{value: 9})])
    eventually(fn -> Server.agent(agent).state.values == [9] end)
    assert :ets.lookup_element(table, :attempt, 2) == 2
  end

  test "Manager owns a Bus named for its Agent by default", %{jido: jido} do
    id = unique_id("managed-bus")
    {:ok, agent} = Jido.start_agent(jido, ManagerAgent, id: id)

    assert {:ok, bus} = Bus.whereis(id, jido: jido)
    assert Server.children(agent)[{:plugin, Manager}].pid == bus

    assert :ok = Jido.stop_agent(jido, agent)
    eventually(fn -> Bus.whereis(id, jido: jido) == {:error, :not_found} end)
  end

  test "one Agent can own a Bus and consume from it", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, OwnedBusAgent, id: unique_id("owned-bus"))
    assert {:ok, bus} = Bus.whereis(:owned_plugin_bus, jido: jido)

    assert {:ok, [_record]} = Bus.publish(bus, [signal("bus.input", %{value: 11})])
    eventually(fn -> Server.agent(agent).state.values == [11] end)
  end

  test "Client ignores stale reconnect messages after reconnecting", %{jido: jido} do
    bus = start_supervised!({Bus, name: :plugin_bus, jido: jido}, id: :reconnect_test_bus)

    init = %Jido.Plugin.Init{
      agent_server: self(),
      agent_id: unique_id("reconnect-token"),
      module: Client,
      jido: jido,
      options: [bus: :plugin_bus, retry_delay_ms: 60_000]
    }

    client = start_supervised!({Jido.Plugin.Bus.Client.Runtime, init})
    assert :ok = GenServer.call(client, :await_ready)
    monitor = Process.monitor(bus)
    assert :ok = stop_supervised(:reconnect_test_bus)
    assert_receive {:DOWN, ^monitor, :process, ^bus, :shutdown}

    token = eventually(fn -> :sys.get_state(client).reconnect_token end)
    send(client, {:reconnect, token})
    # The call is a barrier after the failed reconnect attempt.
    assert {:error, :not_ready} = GenServer.call(client, :await_ready)
    next_token = :sys.get_state(client).reconnect_token
    assert is_reference(next_token)
    refute next_token == token

    new_bus = start_supervised!({Bus, name: :plugin_bus, jido: jido}, id: :reconnect_test_bus)
    send(client, {:reconnect, token})
    assert {:error, :not_ready} = GenServer.call(client, :await_ready)
    assert :sys.get_state(client).reconnect_token == next_token

    send(client, {:reconnect, next_token})
    assert :ok = GenServer.call(client, :await_ready)
    connected = :sys.get_state(client)
    assert connected.bus == new_bus
    assert connected.reconnect_token == nil

    send(client, {:reconnect, token})
    send(client, {:reconnect, next_token})
    assert :sys.get_state(client) == connected
  end

  test "Client reconnects when its owned Bus restarts", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, OwnedBusAgent, id: unique_id("owned-restart"))
    children = Server.children(agent)
    bus = children[{:plugin, Manager}].pid
    client = children[{:plugin, Client}].pid

    Process.exit(bus, :kill)

    restarted_bus =
      eventually(fn ->
        case Server.children(agent)[{:plugin, Manager}].pid do
          pid when is_pid(pid) and pid != bus -> pid
          _other -> nil
        end
      end)

    eventually(fn -> match?(%{bus: ^restarted_bus}, :sys.get_state(client)) end)
    assert {:ok, [_record]} = Bus.publish(restarted_bus, [signal("bus.input", %{value: 12})])
    eventually(fn -> Server.agent(agent).state.values == [12] end)
  end
end
