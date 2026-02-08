defmodule JidoTest.AgentServer.PluginSubscriptionsTest do
  use JidoTest.Case, async: false

  alias Jido.Sensor.Runtime

  @moduletag :capture_log

  # ---------------------------------------------------------------------------
  # Test Sensor Module
  # ---------------------------------------------------------------------------

  defmodule TestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "test_sensor",
      description: "A sensor for testing plugin subscriptions",
      schema:
        Zoi.object(
          %{
            emit_on_init: Zoi.boolean() |> Zoi.default(false),
            signal_type: Zoi.string() |> Zoi.default("test.sensor.event")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      state = %{
        config: config,
        context: context,
        event_count: 0
      }

      if config.emit_on_init do
        signal =
          Jido.Signal.new!(%{
            source: "/sensor/test",
            type: config.signal_type,
            data: %{event: :initialized, context_keys: Map.keys(context)}
          })

        {:ok, state, [{:emit, signal}]}
      else
        {:ok, state}
      end
    end

    @impl Jido.Sensor
    def handle_event({:trigger, value}, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/test",
          type: state.config.signal_type,
          data: %{value: value, count: state.event_count + 1}
        })

      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state, [{:emit, signal}]}
    end

    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule SecondTestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "second_test_sensor",
      description: "A second sensor for multi-sensor tests",
      schema:
        Zoi.object(
          %{
            sensor_id: Zoi.string() |> Zoi.default("second")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/#{config.sensor_id}",
          type: "second.sensor.init",
          data: %{sensor_id: config.sensor_id, agent_id: context.agent_id}
        })

      {:ok, %{config: config, context: context}, [{:emit, signal}]}
    end

    @impl Jido.Sensor
    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule CrashSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "crash_sensor",
      description: "A sensor that crashes on demand",
      schema: Zoi.object(%{}, coerce: true)

    @impl Jido.Sensor
    def init(_config, context) do
      {:ok, %{context: context}}
    end

    @impl Jido.Sensor
    def handle_event(:crash, _state) do
      raise "intentional crash for trap_exit test"
    end

    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Test Action Module
  # ---------------------------------------------------------------------------

  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Test Plugin Modules
  # ---------------------------------------------------------------------------

  defmodule PluginWithSensor do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_sensor",
      state_key: :with_sensor,
      actions: [JidoTest.AgentServer.PluginSubscriptionsTest.SimpleAction]

    @impl Jido.Plugin
    def subscriptions(_config, context) do
      [
        {JidoTest.AgentServer.PluginSubscriptionsTest.TestSensor,
         %{emit_on_init: true, signal_type: "plugin.sensor.ready", agent_ref: context.agent_ref}}
      ]
    end
  end

  defmodule PluginWithMultipleSensors do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_multiple_sensors",
      state_key: :multi_sensors,
      actions: [JidoTest.AgentServer.PluginSubscriptionsTest.SimpleAction]

    @impl Jido.Plugin
    def subscriptions(_config, context) do
      [
        {JidoTest.AgentServer.PluginSubscriptionsTest.TestSensor,
         %{emit_on_init: true, signal_type: "first.sensor.event", agent_ref: context.agent_ref}},
        {JidoTest.AgentServer.PluginSubscriptionsTest.SecondTestSensor,
         %{sensor_id: "multi-test", agent_ref: context.agent_ref}}
      ]
    end
  end

  defmodule PluginWithNoSubscriptions do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_no_subscriptions",
      state_key: :no_subs,
      actions: [JidoTest.AgentServer.PluginSubscriptionsTest.SimpleAction]

    @impl Jido.Plugin
    def subscriptions(_config, _context) do
      []
    end
  end

  defmodule PluginWithoutSubscriptionsCallback do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_without_subscriptions_callback",
      state_key: :no_callback,
      actions: [JidoTest.AgentServer.PluginSubscriptionsTest.SimpleAction]
  end

  defmodule PluginWithCrashSensor do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_crash_sensor",
      state_key: :crash_sensor_plugin,
      actions: [JidoTest.AgentServer.PluginSubscriptionsTest.SimpleAction]

    @impl Jido.Plugin
    def subscriptions(_config, _context) do
      [{JidoTest.AgentServer.PluginSubscriptionsTest.CrashSensor, %{}}]
    end
  end

  # ---------------------------------------------------------------------------
  # Test Agent Modules
  # ---------------------------------------------------------------------------

  defmodule AgentWithSensorPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_sensor_plugin",
      plugins: [JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithSensor]
  end

  defmodule AgentWithMultiSensorPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_multi_sensor_plugin",
      plugins: [JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithMultipleSensors]
  end

  defmodule AgentWithNoSubscriptionsPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_no_subs_plugin",
      plugins: [JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithNoSubscriptions]
  end

  defmodule AgentWithPluginWithoutCallback do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_plugin_without_callback",
      plugins: [JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithoutSubscriptionsCallback]
  end

  defmodule AgentWithMultiplePlugins do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_multiple_plugins",
      plugins: [
        JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithSensor,
        JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithMultipleSensors
      ]
  end

  defmodule AgentWithCrashSensorPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_crash_sensor_plugin",
      plugins: [JidoTest.AgentServer.PluginSubscriptionsTest.PluginWithCrashSensor]
  end

  defp sensor_children(state) do
    Enum.filter(state.children, fn {tag, _child_info} -> match?({:sensor, _, _}, tag) end)
  end

  defp await_sensor_children(pid, expected_count) do
    eventually_state(pid, fn state ->
      length(sensor_children(state)) == expected_count
    end)

    {:ok, state} = Jido.AgentServer.state(pid)
    sensor_children(state)
  end

  # ---------------------------------------------------------------------------
  # Tests
  # ---------------------------------------------------------------------------

  describe "plugin subscription sensors during post_init" do
    test "starts subscription sensor during post_init", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)

      sensor_children = await_sensor_children(pid, 1)

      assert length(sensor_children) == 1

      [{tag, child_info}] = sensor_children
      assert {:sensor, PluginWithSensor, TestSensor} = tag
      assert Process.alive?(child_info.pid)

      GenServer.stop(pid)
    end

    test "sensor is monitored by AgentServer", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)

      [{_tag, child_info}] = await_sensor_children(pid, 1)
      assert child_info.ref != nil

      GenServer.stop(child_info.pid)

      eventually_state(pid, fn state ->
        sensor_count =
          state.children
          |> Enum.count(fn {tag, _} -> match?({:sensor, _, _}, tag) end)

        sensor_count == 0
      end)

      GenServer.stop(pid)
    end

    test "sensor runtime is started under supervisor and not linked to AgentServer", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)

      [{_tag, child_info}] = await_sensor_children(pid, 1)

      links = Process.info(child_info.pid, :links) |> elem(1)
      refute pid in links

      GenServer.stop(pid)
    end
  end

  describe "sensor context" do
    test "sensor receives correct context with agent_ref, agent_id, agent_module, plugin_spec", %{
      jido: jido
    } do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)
      [{_tag, child_info}] = await_sensor_children(pid, 1)

      sensor_state = :sys.get_state(child_info.pid)

      assert is_map(sensor_state.context)
      assert is_binary(sensor_state.context.agent_id)
      assert sensor_state.context.agent_module == AgentWithSensorPlugin
      assert is_tuple(sensor_state.context.agent_ref)
      assert sensor_state.context.plugin_spec != nil
      assert sensor_state.context.plugin_spec.module == PluginWithSensor
      assert sensor_state.context.jido_instance == jido

      GenServer.stop(pid)
    end
  end

  describe "signal delivery to agent" do
    test "sensor signals are delivered to the agent", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)
      [{_tag, child_info}] = await_sensor_children(pid, 1)

      Runtime.event(child_info.pid, {:trigger, :test_value})

      eventually(fn ->
        runtime_state = :sys.get_state(child_info.pid)
        runtime_state.sensor_state.event_count == 1
      end)

      GenServer.stop(pid)
    end
  end

  describe "multiple sensors from same plugin" do
    test "starts all sensors from plugin with multiple subscriptions", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithMultiSensorPlugin, jido: jido)
      sensor_children = await_sensor_children(pid, 2)

      assert length(sensor_children) == 2

      sensor_modules =
        sensor_children
        |> Enum.map(fn {{:sensor, _plugin, sensor_mod}, _} -> sensor_mod end)
        |> Enum.sort()

      assert sensor_modules == [SecondTestSensor, TestSensor]

      Enum.each(sensor_children, fn {_tag, child_info} ->
        assert Process.alive?(child_info.pid)
      end)

      GenServer.stop(pid)
    end
  end

  describe "multiple plugins with sensors" do
    test "starts sensors from all plugins", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithMultiplePlugins, jido: jido)
      sensor_children = await_sensor_children(pid, 3)

      assert length(sensor_children) == 3

      plugin_sensor_pairs =
        sensor_children
        |> Enum.map(fn {{:sensor, plugin, sensor}, _} -> {plugin, sensor} end)
        |> Enum.sort()

      assert {PluginWithMultipleSensors, SecondTestSensor} in plugin_sensor_pairs
      assert {PluginWithMultipleSensors, TestSensor} in plugin_sensor_pairs
      assert {PluginWithSensor, TestSensor} in plugin_sensor_pairs

      GenServer.stop(pid)
    end
  end

  describe "plugin with empty subscriptions" do
    test "plugin returning empty list works fine", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithNoSubscriptionsPlugin, jido: jido)
      assert await_sensor_children(pid, 0) == []

      GenServer.stop(pid)
    end

    test "plugin without subscriptions callback works fine", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithPluginWithoutCallback, jido: jido)
      assert await_sensor_children(pid, 0) == []

      GenServer.stop(pid)
    end
  end

  describe "sensor child tracking" do
    test "sensors are tracked in agent's children map", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)
      _ = await_sensor_children(pid, 1)
      {:ok, state} = Jido.AgentServer.state(pid)

      tag = {:sensor, PluginWithSensor, TestSensor}
      assert Map.has_key?(state.children, tag)

      child_info = Map.get(state.children, tag)
      assert child_info.module == TestSensor
      assert child_info.meta.plugin == PluginWithSensor
      assert child_info.meta.sensor == TestSensor

      GenServer.stop(pid)
    end
  end

  describe "sensor cleanup on AgentServer stop" do
    test "sensors are cleaned up when AgentServer stops", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithSensorPlugin, jido: jido)
      sensor_children = await_sensor_children(pid, 1)

      sensor_pids = Enum.map(sensor_children, fn {_, info} -> info.pid end)

      assert Enum.all?(sensor_pids, &Process.alive?/1)

      GenServer.stop(pid)

      eventually(fn ->
        not Process.alive?(pid)
      end)
    end
  end

  describe "linked sensor crashes" do
    test "crashing sensor does not crash AgentServer", %{jido: jido} do
      Process.flag(:trap_exit, true)

      {:ok, pid} = Jido.AgentServer.start_link(agent: AgentWithCrashSensorPlugin, jido: jido)
      [{_tag, child_info}] = await_sensor_children(pid, 1)

      Runtime.event(child_info.pid, :crash)

      eventually(fn -> not Process.alive?(child_info.pid) end)

      refute_receive {:EXIT, ^pid, _reason}, 100
      assert Process.alive?(pid)

      eventually_state(pid, fn latest_state ->
        latest_state.children
        |> Enum.count(fn {tag, _} -> match?({:sensor, _, _}, tag) end)
        |> Kernel.==(0)
      end)

      GenServer.stop(pid)
    end
  end
end
