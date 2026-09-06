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

  defmodule ControlledSensor do
    use GenServer

    def child_spec(%Init{config: %{failure: :raise}}), do: raise("invalid sensor spec")
    def child_spec(%Init{config: %{failure: :throw}}), do: throw(:invalid_sensor_spec)
    def child_spec(init), do: super(init)

    def start_link(%Init{config: %{gate: gate}} = init) do
      case Elixir.Agent.get_and_update(gate, fn
             [result | rest] -> {result, rest}
             [] -> {:ok, []}
           end) do
        :ok ->
          GenServer.start_link(__MODULE__, init)

        :with_info ->
          {:ok, pid} = GenServer.start_link(__MODULE__, init)
          {:ok, pid, :sensor_info}

        :ignore ->
          :ignore

        {:error, reason} ->
          {:error, reason}
      end
    end

    @impl true
    def init(init), do: {:ok, init}
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

  test "reuses unchanged sensors and replaces changed configurations", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, Agent)
    runtime = Server.children(agent)[{:plugin, SensorManager}].pid
    desired = %{source: %{module: TestSensor, config: %{value: 3}}}

    assert :ok = Runtime.reconcile(runtime, desired, 1, 1_000)
    first = Runtime.sensors(runtime).source
    assert :ok = Runtime.reconcile(runtime, desired, 2, 1_000)
    assert Runtime.sensors(runtime).source == first

    changed = put_in(desired.source.config.value, 4)
    assert :ok = Runtime.reconcile(runtime, changed, 2, 1_000)
    assert Runtime.sensors(runtime).source == first

    ref = Process.monitor(first)
    assert :ok = Runtime.reconcile(runtime, changed, 3, 1_000)
    assert_receive {:DOWN, ^ref, :process, ^first, :shutdown}
    assert Runtime.sensors(runtime).source != first
    eventually(fn -> Server.agent(agent).state.readings == [3, 4] end)
  end

  test "retries failed starts and failed restarts without a new command", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, Agent)
    runtime = Server.children(agent)[{:plugin, SensorManager}].pid
    gate = start_supervised!({Elixir.Agent, fn -> [{:error, :offline}, :ignore, :with_info] end})
    desired = %{source: %{module: ControlledSensor, config: %{gate: gate}}}

    assert {:error, {:sensor_start_failed, :source, :offline}} =
             Runtime.reconcile(runtime, desired, 1, 1_000)

    first = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    assert Process.alive?(first)
    Elixir.Agent.update(gate, fn _ -> [{:error, :offline}, :ok] end)
    Process.exit(first, :kill)

    replacement =
      eventually(fn ->
        case Runtime.sensors(runtime)[:source] do
          pid when is_pid(pid) and pid != first -> pid
          _ -> nil
        end
      end)

    assert Process.alive?(replacement)

    controller = child_pid(runtime, Jido.Plugin.SensorManager.Runtime.Controller)
    send(controller, {:retry_reconcile, make_ref(), -1})
    send(controller, {:DOWN, make_ref(), :process, self(), :normal})
    assert Runtime.sensors(runtime) == %{source: replacement}
  end

  test "invalid child specs return errors and removing them cancels retries", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, Agent)
    runtime = Server.children(agent)[{:plugin, SensorManager}].pid

    for {failure, reason, version} <- [
          {:raise, %RuntimeError{message: "invalid sensor spec"}, 1},
          {:throw, {:throw, :invalid_sensor_spec}, 2}
        ] do
      desired = %{source: %{module: ControlledSensor, config: %{failure: failure}}}

      assert {:error, {:sensor_start_failed, :source, ^reason}} =
               Runtime.reconcile(runtime, desired, version, 1_000)

      assert Runtime.sensors(runtime) == %{}
    end

    assert :ok = Runtime.reconcile(runtime, %{}, 3, 1_000)
    assert Runtime.sensors(runtime) == %{}
    assert Process.alive?(runtime)
  end

  defp child_pid(supervisor, id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {^id, pid, _type, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
  end

  test "sensor Directives reject nonportable data and invalid modules" do
    for {directive, message} <- [
          {SensorManager.start(nil, TestSensor), "Sensor tag must not be nil"},
          {SensorManager.stop(self()), "Sensor tag must contain portable data"},
          {SensorManager.start(:source, String), "Sensor must define child_spec/1"},
          {SensorManager.start(:source, TestSensor, %{pid: self()}),
           "Sensor config must contain portable data"}
        ] do
      assert {:error, error} = SensorManager.validate_directive(directive, [])
      assert error.message == message
    end
  end

  test "calls to an unavailable sensor runtime return errors" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert {:error, {:sensor_manager_runtime_unavailable, _}} = SensorManager.await_ready(pid, [])

    context =
      struct(Jido.Plugin.DirectiveContext, plugin_state: %{desired: %{}}, state_version: 1)

    assert {:error, {:sensor_manager_runtime_unavailable, _}} =
             SensorManager.dispatch(pid, SensorManager.stop(:source), context, [])
  end
end
