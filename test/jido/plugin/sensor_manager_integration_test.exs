defmodule Jido.Plugin.SensorManagerIntegrationTest do
  use Jido.Test.Case, async: true

  alias Jido.AgentServer
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Runtime
  alias Jido.Test.Plugin.SensorManagerFixtures, as: F

  test "AgentServer commits desired sensors and processes their input", %{jido: jido} do
    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(jido, F.Agent, id: unique_id("sensor-manager-integration"))

    runtime = Jido.Test.AgentServer.Assertions.plugin(server, SensorManager).pid

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(server, signal("sensor.manage", %{operation: :start, value: 7}))

    committed = AgentServer.snapshot(server).agent

    assert committed.state.sensors.desired == %{
             source: %{module: F.EmittingSensor, config: %{value: 7}}
           }

    first_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    eventually(fn -> AgentServer.snapshot(server).agent.state.readings == [7] end)

    Process.exit(first_sensor, :kill)

    second_sensor =
      eventually(fn ->
        case Runtime.sensors(runtime)[:source] do
          pid when is_pid(pid) and pid != first_sensor -> pid
          _other -> nil
        end
      end)

    eventually(fn -> AgentServer.snapshot(server).agent.state.readings == [7, 7] end)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             AgentServer.call(server, signal("sensor.manage", %{operation: :stop}))

    stopped = AgentServer.snapshot(server).agent
    assert stopped.state.sensors.desired == %{}
    eventually(fn -> Runtime.sensors(runtime) == %{} end)
    refute Process.alive?(second_sensor)
  end
end
