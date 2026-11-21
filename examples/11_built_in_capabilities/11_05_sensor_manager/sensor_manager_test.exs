Code.require_file("sensor_manager.ex", __DIR__)

defmodule Jido.Examples.Capabilities.SensorManagerTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.Capabilities.SensorManager.{Agent, ReadingSensor}

  setup do
    instance = :"sensor_manager_example_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: instance}, id: instance)
    {:ok, instance: instance}
  end

  test "a desired sensor starts, recovers, changes, and stops", %{instance: instance} do
    id = "sensor-manager-#{System.unique_integer([:positive])}"
    {:ok, server} = Jido.start_agent(instance, Agent, id: id)
    assert :ok = AgentServer.await_ready(server)

    snapshot = AgentServer.snapshot(server)
    agent_id = snapshot.agent.id
    tag = "temperature"

    assert {:ok, start_signal} = Agent.start_sensor_signal(%{tag: tag, multiplier: 2})
    assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, start_signal)

    first = eventually(fn -> ReadingSensor.whereis(agent_id, tag) end)
    assert is_pid(first)
    assert Process.alive?(first)

    ReadingSensor.push(first, 3)
    assert eventually(fn -> readings(server) == [%{tag: tag, value: 6}] end)

    first_monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^first_monitor, :process, ^first, :killed}, 1_000

    replacement =
      eventually(fn ->
        case ReadingSensor.whereis(agent_id, tag) do
          pid when is_pid(pid) and pid != first -> pid
          _other -> nil
        end
      end)

    assert is_pid(replacement)
    ReadingSensor.push(replacement, 4)

    assert eventually(fn ->
             readings(server) == [
               %{tag: tag, value: 6},
               %{tag: tag, value: 8}
             ]
           end)

    assert {:ok, replace_signal} = Agent.start_sensor_signal(%{tag: tag, multiplier: 3})
    assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, replace_signal)

    reconfigured =
      eventually(fn ->
        case ReadingSensor.whereis(agent_id, tag) do
          pid when is_pid(pid) and pid != replacement -> pid
          _other -> nil
        end
      end)

    assert is_pid(reconfigured)
    ReadingSensor.push(reconfigured, 5)

    assert eventually(fn ->
             readings(server) == [
               %{tag: tag, value: 6},
               %{tag: tag, value: 8},
               %{tag: tag, value: 15}
             ]
           end)

    assert {:ok, stop_signal} = Agent.stop_sensor_signal(%{tag: tag})
    assert {:ok, %AgentServer.TurnResult{status: :committed}} = AgentServer.call(server, stop_signal)
    assert eventually(fn -> ReadingSensor.whereis(agent_id, tag) == nil end)

    desired = AgentServer.snapshot(server).agent.state.sensors.desired
    assert desired == %{}

    assert :ok = Jido.stop_agent(instance, server)
  end

  defp readings(server), do: AgentServer.snapshot(server).agent.state.readings

  defp eventually(fun, attempts \\ 200)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    case fun.() do
      value when value in [nil, false] ->
        receive do
        after
          10 -> eventually(fun, attempts - 1)
        end

      value ->
        value
    end
  end
end
