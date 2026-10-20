defmodule Jido.Plugin.SensorManagerIntegrationTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Runtime
  alias JidoTest.Plugin.SensorManagerFixtures, as: F

  test "AgentServer commits desired sensors and processes their input", %{jido: jido} do
    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(jido, F.Agent,
        id: unique_id("sensor-manager-integration")
      )

    runtime = JidoTest.AgentServerAssertions.plugin(server, SensorManager).pid

    assert {:ok, committed, _directives} =
             AgentServer.call(server, signal("sensor.manage", %{operation: :start, value: 7}))

    assert committed.state.sensors.desired == %{
             source: %{module: F.EmittingSensor, config: %{value: 7}}
           }

    first_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    eventually(fn -> AgentServer.agent(server).state.readings == [7] end)

    Process.exit(first_sensor, :kill)

    second_sensor =
      eventually(fn ->
        case Runtime.sensors(runtime)[:source] do
          pid when is_pid(pid) and pid != first_sensor -> pid
          _other -> nil
        end
      end)

    eventually(fn -> AgentServer.agent(server).state.readings == [7, 7] end)

    assert {:ok, stopped, _directives} =
             AgentServer.call(server, signal("sensor.manage", %{operation: :stop}))

    assert stopped.state.sensors.desired == %{}
    eventually(fn -> Runtime.sensors(runtime) == %{} end)
    refute Process.alive?(second_sensor)
  end
end
