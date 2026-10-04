defmodule JidoTest.Examples.Applications.InboxTest do
  use JidoTest.Case, async: false

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Applications.Inbox.{Agent, Sensor}
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Runtime

  test "managed input survives duplicate events, failures, and runtime replacement", %{jido: jido} do
    {:ok, agent_server} = Jido.start_agent(jido, Agent, id: unique_id("inbox"))
    agent_id = Server.agent(agent_server).id
    manager = manager(agent_server)

    assert {:ok, started} = Server.call(agent_server, sensor_signal(:start))
    start_version = Server.snapshot(agent_server).state_version

    desired = %{
      "mailbox" => %{
        module: Sensor,
        config: %{source: "/examples/applications/inbox/mailbox"}
      }
    }

    assert started.state.sensors.desired == desired
    assert {:ok, %{desired: ^desired}} = Server.plugin_state(agent_server, SensorManager)

    sensor = eventually(fn -> Sensor.whereis(agent_id, "mailbox") end)
    push(sensor, ["first", "duplicate", "duplicate"])

    eventually(fn -> Server.agent(agent_server).state.accepted == 2 end)
    assert Enum.count(Server.agent(agent_server).state.seen, &(&1 == "duplicate")) == 1

    sensor_monitor = Process.monitor(sensor)
    Process.exit(sensor, :kill)
    assert_receive {:DOWN, ^sensor_monitor, :process, ^sensor, :killed}, 1_000

    replacement =
      eventually(fn ->
        case Sensor.whereis(agent_id, "mailbox") do
          pid when is_pid(pid) and pid != sensor -> pid
          _pid -> nil
        end
      end)

    Sensor.push(replacement, %{event_id: "after-sensor-restart"})
    eventually(fn -> Server.agent(agent_server).state.accepted == 3 end)

    manager_monitor = Process.monitor(manager)
    Process.exit(manager, :kill)
    assert_receive {:DOWN, ^manager_monitor, :process, ^manager, :killed}, 1_000

    next_manager = eventually(fn -> changed_manager(agent_server, manager) end)

    restored_sensor =
      eventually(fn ->
        case Sensor.whereis(agent_id, "mailbox") do
          pid when is_pid(pid) and pid != replacement -> pid
          _pid -> nil
        end
      end)

    Sensor.push(restored_sensor, %{event_id: "after-manager-restart"})
    eventually(fn -> Server.agent(agent_server).state.accepted == 4 end)

    assert {:ok, stopped} = Server.call(agent_server, sensor_signal(:stop))
    assert stopped.state.sensors.desired == %{}
    eventually(fn -> Sensor.whereis(agent_id, "mailbox") == nil end)

    assert :ok = Runtime.reconcile(next_manager, desired, start_version, 1_000)
    assert Runtime.sensors(next_manager) == %{}
    assert Sensor.whereis(agent_id, "mailbox") == nil

    assert {:ok, _started_again} = Server.call(agent_server, sensor_signal(:start))
    final_sensor = eventually(fn -> Sensor.whereis(agent_id, "mailbox") end)
    final_sensor_monitor = Process.monitor(final_sensor)
    final_manager = manager(agent_server)
    final_manager_monitor = Process.monitor(final_manager)

    assert :ok = Jido.stop_agent(jido, agent_server)
    assert_receive {:DOWN, ^final_sensor_monitor, :process, ^final_sensor, _reason}, 1_000
    assert_receive {:DOWN, ^final_manager_monitor, :process, ^final_manager, _reason}, 1_000
    eventually(fn -> Sensor.whereis(agent_id, "mailbox") == nil end)
  end

  defp push(sensor, event_ids) do
    Enum.each(event_ids, fn event_id ->
      Sensor.push(sensor, %{event_id: event_id})
    end)
  end

  defp sensor_signal(operation) do
    {:ok, signal} = Agent.sensor_signal(%{operation: operation, tag: "mailbox"})
    signal
  end

  defp manager(agent_server) do
    Server.children(agent_server)
    |> Map.fetch!({:plugin, SensorManager})
    |> Map.fetch!(:pid)
  end

  defp changed_manager(agent_server, old_manager) do
    case manager(agent_server) do
      pid when is_pid(pid) and pid != old_manager -> pid
      _pid -> nil
    end
  end
end
