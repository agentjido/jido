defmodule Jido.Plugin.SensorManagerTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Init
  alias Jido.Plugin.SensorManager.Runtime
  alias Jido.Signal

  defmodule TestSensor do
    use GenServer

    def start_link(%Init{} = init), do: GenServer.start_link(__MODULE__, init)

    @impl true
    def init(%Init{} = init) do
      signal = Signal.new!("sensor.reading", %{value: init.config.value}, source: "/sensor/test")
      Server.cast(init.agent_server, signal)
      {:ok, init}
    end
  end

  defmodule ManageAction do
    use Jido.Action, name: "sensor_manager_manage"

    @impl Jido.Action
    def run(%{operation: :start, value: value}, context) do
      {:ok, context.agent_state, [SensorManager.start(:source, TestSensor, %{value: value})]}
    end

    def run(%{operation: :stop}, context) do
      {:ok, context.agent_state, [SensorManager.stop(:source)]}
    end
  end

  defmodule ReadingAction do
    use Jido.Action, name: "sensor_manager_reading"

    @impl Jido.Action
    def run(%{value: value}, context) do
      readings = context.agent_state.readings ++ [value]
      {:ok, %{context.agent_state | readings: readings}}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "sensor_manager_agent",
      schema: Zoi.object(%{readings: Zoi.list(Zoi.integer()) |> Zoi.default([])}),
      routes: [
        {"sensor.manage", ManageAction},
        {"sensor.reading", ReadingAction}
      ],
      plugins: [{SensorManager, retry_delay_ms: 10}]
  end

  test "reconciles desired sensors and restarts a failed sensor", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, Agent, id: unique_id("sensor-manager"))
    runtime = Server.children(agent)[{:plugin, SensorManager}].pid

    assert {:ok, committed} =
             Server.call(agent, signal("sensor.manage", %{operation: :start, value: 7}))

    assert committed.state.sensors.desired == %{
             source: %{module: TestSensor, config: %{value: 7}}
           }

    first_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    eventually(fn -> Server.agent(agent).state.readings == [7] end)

    Process.exit(first_sensor, :kill)

    second_sensor =
      eventually(fn ->
        case Runtime.sensors(runtime)[:source] do
          pid when is_pid(pid) and pid != first_sensor -> pid
          _other -> nil
        end
      end)

    assert Process.alive?(second_sensor)
    eventually(fn -> Server.agent(agent).state.readings == [7, 7] end)

    assert {:ok, stopped} =
             Server.call(agent, signal("sensor.manage", %{operation: :stop}))

    assert stopped.state.sensors.desired == %{}
    eventually(fn -> Runtime.sensors(runtime) == %{} end)
    refute Process.alive?(second_sensor)
  end

  test "restores sensors when an internal supervisor fails", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, Agent, id: unique_id("sensor-supervisor"))
    runtime = Server.children(agent)[{:plugin, SensorManager}].pid

    assert {:ok, _committed} =
             Server.call(agent, signal("sensor.manage", %{operation: :start, value: 5}))

    first_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    eventually(fn -> Server.agent(agent).state.readings == [5] end)

    dynamic_supervisor = child_pid(runtime, DynamicSupervisor)
    controller = child_pid(runtime, Jido.Plugin.SensorManager.Runtime.Controller)
    Process.exit(dynamic_supervisor, :kill)

    eventually(fn ->
      next_dynamic = child_pid(runtime, DynamicSupervisor)
      next_controller = child_pid(runtime, Jido.Plugin.SensorManager.Runtime.Controller)
      next_dynamic != dynamic_supervisor and next_controller != controller
    end)

    second_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    assert second_sensor != first_sensor
    eventually(fn -> Server.agent(agent).state.readings == [5, 5] end)
  end

  defp child_pid(supervisor, id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {^id, pid, _type, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
  end
end
