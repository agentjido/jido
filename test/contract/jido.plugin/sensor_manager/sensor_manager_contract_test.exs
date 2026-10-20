defmodule JidoTest.Contract.PluginSensorManagerTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.plugin.sensor_manager", async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Plugin.Reduction
  alias Jido.AgentServer
  alias Jido.Plugin.DirectiveContext
  alias Jido.Plugin.Init, as: PluginInit
  alias Jido.Plugin.SensorManager
  alias Jido.Plugin.SensorManager.Agent, as: SensorState
  alias Jido.Plugin.SensorManager.Init, as: SensorInit
  alias Jido.Plugin.SensorManager.Runtime
  alias Jido.Plugin.SensorManager.Runtime.Controller
  alias Jido.Plugin.SensorManager.Server
  alias Jido.Plugin.SensorManager.Start
  alias Jido.Plugin.SensorManager.Stop
  alias JidoTest.Plugin.SensorManagerFixtures, as: F

  defp reduction(plugin_state, directives) do
    %Reduction{
      plugin: SensorManager,
      agent_id: "sensor-manager-contract",
      agent_module: __MODULE__,
      signal: Jido.Signal.new!("sensor.contract", %{}, source: "/contract"),
      state_before: %{sensors: plugin_state},
      state: %{sensors: plugin_state},
      plugin_state: plugin_state,
      prepared_input: nil,
      directives: directives
    }
  end

  defp start_agent(jido, opts \\ []) do
    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(
        jido,
        F.Agent,
        Keyword.put_new(opts, :id, unique_id("sensor-manager-contract"))
      )

    runtime = JidoTest.AgentServerAssertions.plugin(server, SensorManager).pid
    {server, runtime}
  end

  @tag obligation: "jido.plugin.sensor_manager.I1"
  test "constructors and schemas define valid portable sensor Directives" do
    start = SensorManager.start({:source, 1}, F.ControlledSensor, %{mode: :poll})
    stop = SensorManager.stop({:source, 1})

    assert start == %Start{
             tag: {:source, 1},
             sensor: F.ControlledSensor,
             config: %{mode: :poll}
           }

    assert stop == %Stop{tag: {:source, 1}}
    assert %Zoi.Types.Struct{module: Start} = Start.schema()
    assert %Zoi.Types.Struct{module: Stop} = Stop.schema()
    assert {:ok, ^start} = Directive.validate(start)
    assert {:ok, ^stop} = Directive.validate(stop)
  end

  @tag obligation: "jido.plugin.sensor_manager.I1"
  test "Directive validation rejects each invalid owned value at its path" do
    cases = [
      {SensorManager.start(nil, F.ControlledSensor), "Sensor tag must not be nil", %{tag: nil}},
      {SensorManager.stop(self()), "Sensor tag must contain portable data", %{path: [:tag]}},
      {SensorManager.start(<<5::3>>, F.ControlledSensor), "Sensor tag must contain portable data",
       %{path: [:tag]}},
      {SensorManager.stop({:source, [<<5::3>>]}), "Sensor tag must contain portable data",
       %{path: [:tag, 1, 0]}},
      {SensorManager.start(:source, String), "Sensor must define child_spec/1",
       %{sensor: String}},
      {SensorManager.start(:source, F.ControlledSensor, %{pid: self()}),
       "Sensor config must contain portable data", %{path: [:config, :pid]}},
      {SensorManager.start(:source, F.ControlledSensor, %{nested: [%{bits: <<5::3>>}]}),
       "Sensor config must contain portable data", %{path: [:config, :nested, 0, :bits]}}
    ]

    for {directive, message, details} <- cases do
      assert {:error,
              %Jido.Error.ValidationError{
                message: ^message,
                kind: :config,
                details: ^details
              }} = Directive.validate(directive)
    end
  end

  @tag obligation: "jido.plugin.sensor_manager.I2"
  test "the Plugin reduces Start and Stop Directives in their given order" do
    assert {:sensors, schema} = SensorState.state_spec([])
    assert {:ok, %{desired: %{}}} = Jido.Schema.parse(schema, %{}, :initialize)
    assert SensorState.directives([]) == [Start, Stop]

    first = SensorManager.start(:source, F.ControlledSensor, %{value: 1})
    replacement = SensorManager.start(:source, F.ControlledSensor, %{value: 2})
    other = SensorManager.start(:other, F.ControlledSensor, %{value: 3})
    unrelated = Directive.emit(Jido.Signal.new!("sensor.other", %{}, source: "/contract"))

    input =
      reduction(%{desired: %{}}, [
        first,
        unrelated,
        replacement,
        SensorManager.stop(:missing),
        other,
        SensorManager.stop(:source)
      ])

    assert {:ok,
            %{
              desired: %{
                other: %{module: F.ControlledSensor, config: %{value: 3}}
              }
            }} = SensorState.reduce(input, [])

    existing = %{desired: %{source: %{module: F.ControlledSensor, config: %{value: 1}}}}

    assert {:ok, %{desired: %{}}} =
             existing
             |> reduction([SensorManager.stop(:source)])
             |> SensorState.reduce([])
  end

  @tag obligation: "jido.plugin.sensor_manager.I3"
  test "retry configuration, runtime ownership, and sensor Init are bounded" do
    for delay <- [1, 1_000, 4_294_967_295] do
      assert :ok = Server.validate_options(retry_delay_ms: delay)
    end

    assert :ok = Server.validate_options([])

    for delay <- [-1, 0, 1.5, :manual, 4_294_967_296] do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Sensor Manager retry delay is invalid",
                kind: :config,
                details: %{retry_delay_ms: ^delay}
              }} = Server.validate_options(retry_delay_ms: delay)
    end

    init = %PluginInit{
      agent_server: self(),
      agent_id: "sensor-manager-contract",
      module: SensorManager,
      plugin_state: %{desired: %{}},
      state_version: 0,
      options: []
    }

    spec = Server.child_spec(init)
    assert spec.id == SensorManager
    assert Map.get(spec, :restart, :permanent) == :permanent
    assert spec.start == {Runtime, :start_link, [init]}

    assert {:ok, %{retry_delay_ms: 1_000}, {:continue, :restore}} =
             Controller.init({init, self()})

    configured_init = %{init | options: [retry_delay_ms: 42]}

    assert {:ok, %{retry_delay_ms: 42}, {:continue, :restore}} =
             Controller.init({configured_init, self()})

    sensor_init = %SensorInit{
      agent_server: self(),
      agent_id: "sensor-manager-contract",
      tag: :source,
      module: F.ControlledSensor,
      config: %{},
      jido: :contract_jido,
      partition: {:tenant, 1}
    }

    assert %Zoi.Types.Struct{module: SensorInit} = SensorInit.schema()
    assert {:ok, ^sensor_init} = Zoi.parse(SensorInit.schema(), Map.from_struct(sensor_init))
  end

  @tag obligation: "jido.plugin.sensor_manager.I4"
  test "reconciliation reuses exact sensors and changes only a newer differing tag", %{jido: jido} do
    {_server, runtime} = start_agent(jido, partition: "contract")
    gate = start_supervised!({Elixir.Agent, fn -> [:ok, :ok, :ok] end})

    desired = %{
      changed: %{module: F.ControlledSensor, config: %{gate: gate, value: 1}},
      unchanged: %{module: F.ControlledSensor, config: %{gate: gate, value: 2}}
    }

    assert :ok = Runtime.reconcile(runtime, desired, 1, 1_000)
    first = Runtime.sensors(runtime)
    assert Map.keys(first) |> Enum.sort() == [:changed, :unchanged]

    changed_init = :sys.get_state(first.changed)
    assert changed_init.tag == :changed
    assert changed_init.module == F.ControlledSensor
    assert changed_init.config == desired.changed.config
    assert changed_init.jido == jido
    assert changed_init.partition == "contract"

    assert :ok = Runtime.reconcile(runtime, desired, 2, 1_000)
    assert Runtime.sensors(runtime) == first

    changed = put_in(desired.changed.config.value, 1.0)
    changed_ref = Process.monitor(first.changed)
    assert :ok = Runtime.reconcile(runtime, changed, 3, 1_000)
    assert_receive {:DOWN, ^changed_ref, :process, changed_pid, :shutdown}
    assert changed_pid == first.changed

    next = Runtime.sensors(runtime)
    assert next.changed != first.changed
    assert next.unchanged == first.unchanged

    assert :ok = Runtime.reconcile(runtime, %{unchanged: changed.unchanged}, 4, 1_000)
    assert Runtime.sensors(runtime) == %{unchanged: first.unchanged}
    refute Process.alive?(next.changed)
  end

  @tag obligation: "jido.plugin.sensor_manager.I5"
  test "restoration records its revision before it accepts live reconciliation", %{jido: jido} do
    {_server, runtime} = start_agent(jido)
    gate = start_supervised!({Elixir.Agent, fn -> [:ok] end})
    desired = %{source: %{module: F.ControlledSensor, config: %{gate: gate}}}

    assert :ok = Runtime.reconcile(runtime, desired, 0, 1_000)
    assert Runtime.sensors(runtime) == %{}

    assert :ok = Runtime.reconcile(runtime, desired, 1, 1_000)
    assert %{source: sensor} = Runtime.sensors(runtime)
    assert Process.alive?(sensor)

    assert :ok = Runtime.reconcile(runtime, %{}, 1, 1_000)
    assert Runtime.sensors(runtime) == %{source: sensor}
  end

  @tag obligation: "jido.plugin.sensor_manager.I6"
  test "sensor and internal supervisor failure restore the desired set", %{jido: jido} do
    {server, runtime} = start_agent(jido)

    assert {:ok, _agent, _directives} =
             AgentServer.call(server, signal("sensor.manage", %{operation: :start, value: 5}))

    first_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    Process.exit(first_sensor, :kill)

    second_sensor =
      eventually(fn ->
        case Runtime.sensors(runtime)[:source] do
          pid when is_pid(pid) and pid != first_sensor -> pid
          _other -> nil
        end
      end)

    first_dynamic = F.child_pid(runtime, DynamicSupervisor)
    first_controller = F.child_pid(runtime, Controller)
    Process.exit(first_dynamic, :kill)

    eventually(fn ->
      next_dynamic = F.child_pid(runtime, DynamicSupervisor)
      next_controller = F.child_pid(runtime, Controller)
      next_dynamic != first_dynamic and next_controller != first_controller
    end)

    third_sensor = eventually(fn -> Runtime.sensors(runtime)[:source] end)
    assert third_sensor != second_sensor
    assert Process.alive?(third_sensor)
  end

  @tag obligation: ["jido.plugin.sensor_manager.I5", "jido.plugin.sensor_manager.I7"]
  test "newer success cancels failed reconciliation and its stale retry", %{jido: jido} do
    {_server, runtime} = start_agent(jido)
    controller = F.child_pid(runtime, Controller)
    gate = start_supervised!({Elixir.Agent, fn -> [{:error, :offline}, :ok] end})
    old = %{source: %{module: F.ControlledSensor, config: %{gate: gate}}}

    assert {:error, {:sensor_start_failed, :source, :offline}} =
             Runtime.reconcile(runtime, old, 1, 1_000)

    old_retry = :sys.get_state(controller).retry_token
    assert is_reference(old_retry)

    assert :ok = Runtime.reconcile(runtime, %{}, 2, 1_000)
    assert Runtime.sensors(runtime) == %{}

    assert :ok = Runtime.reconcile(runtime, old, 1, 1_000)
    send(controller, {:retry_reconcile, old_retry, 1})
    assert Runtime.sensors(runtime) == %{}

    controller_state = :sys.get_state(controller)
    assert controller_state.last_reconciled_version == 2
    assert controller_state.retry_timer == nil
    assert controller_state.retry_token == nil
  end

  @tag obligation: [
         "jido.plugin.sensor_manager.I6",
         "jido.plugin.sensor_manager.I7",
         "jido.plugin.sensor_manager.I8"
       ]
  test "failed starts and restarts retry without a new Directive", %{jido: jido} do
    {_server, runtime} = start_agent(jido)

    gate =
      start_supervised!({Elixir.Agent, fn -> [{:error, :offline}, :ignore, :with_info] end})

    desired = %{source: %{module: F.ControlledSensor, config: %{gate: gate}}}

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
          _other -> nil
        end
      end)

    assert Process.alive?(replacement)

    controller = F.child_pid(runtime, Controller)
    send(controller, {:retry_reconcile, make_ref(), -1})
    send(controller, {:DOWN, make_ref(), :process, self(), :normal})
    assert Runtime.sensors(runtime) == %{source: replacement}
  end

  @tag obligation: "jido.plugin.sensor_manager.I8"
  test "invalid child specifications fail without damaging the runtime", %{jido: jido} do
    {_server, runtime} = start_agent(jido)

    for {failure, reason, version} <- [
          {:raise, %RuntimeError{message: "invalid sensor spec"}, 1},
          {:throw, {:throw, :invalid_sensor_spec}, 2}
        ] do
      desired = %{source: %{module: F.ControlledSensor, config: %{failure: failure}}}

      assert {:error, {:sensor_start_failed, :source, ^reason}} =
               Runtime.reconcile(runtime, desired, version, 1_000)

      assert Runtime.sensors(runtime) == %{}
    end

    assert :ok = Runtime.reconcile(runtime, %{}, 3, 1_000)
    assert Runtime.sensors(runtime) == %{}
    assert Process.alive?(runtime)
  end

  @tag obligation: "jido.plugin.sensor_manager.I8"
  test "Server callbacks contain an unavailable runtime exit" do
    runtime = spawn(fn -> :ok end)
    ref = Process.monitor(runtime)
    assert_receive {:DOWN, ^ref, :process, ^runtime, _reason}

    assert {:error, {:sensor_manager_runtime_unavailable, _reason}} =
             Server.await_ready(runtime, [])

    context = struct(DirectiveContext, plugin_state: %{desired: %{}}, state_version: 1)

    assert {:error, {:sensor_manager_runtime_unavailable, _reason}} =
             Server.dispatch(runtime, SensorManager.stop(:source), context, [])
  end
end
