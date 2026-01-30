defmodule JidoTest.Sensor.RuntimeTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Jido.Sensor.Runtime

  defmodule SimpleSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "simple_sensor",
      description: "A simple test sensor",
      schema:
        Zoi.object(
          %{
            prefix: Zoi.string() |> Zoi.default("test")
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      state = %{
        prefix: config.prefix,
        context: context,
        event_count: 0
      }

      {:ok, state}
    end

    @impl Jido.Sensor
    def handle_event({:data, value}, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/#{state.prefix}",
          type: "#{state.prefix}.data.received",
          data: %{value: value, count: state.event_count + 1}
        })

      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state, [{:emit, signal}]}
    end

    def handle_event(:noop, state) do
      {:ok, state}
    end

    def handle_event({:error, reason}, _state) do
      {:error, reason}
    end
  end

  defmodule SchedulingSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "scheduling_sensor",
      description: "A sensor that schedules ticks on init",
      schema:
        Zoi.object(
          %{
            interval: Zoi.integer() |> Zoi.default(100)
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      interval = config.interval

      state = %{
        interval: interval,
        context: context,
        tick_count: 0
      }

      {:ok, state, [{:schedule, interval}]}
    end

    @impl Jido.Sensor
    def handle_event(:tick, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/scheduling",
          type: "sensor.tick",
          data: %{tick: state.tick_count + 1}
        })

      new_state = %{state | tick_count: state.tick_count + 1}
      {:ok, new_state, [{:emit, signal}]}
    end
  end

  defmodule CustomEventSchedulingSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "custom_event_sensor",
      description: "A sensor that schedules custom events",
      schema:
        Zoi.object(
          %{
            interval: Zoi.integer() |> Zoi.default(50)
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      interval = config.interval

      state = %{
        interval: interval,
        context: context,
        event_count: 0
      }

      {:ok, state, [{:schedule, interval, :custom_event}]}
    end

    @impl Jido.Sensor
    def handle_event(:custom_event, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/custom",
          type: "sensor.custom_event",
          data: %{count: state.event_count + 1}
        })

      new_state = %{state | event_count: state.event_count + 1}
      {:ok, new_state, [{:emit, signal}]}
    end
  end

  defmodule MinimalSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "minimal_sensor",
      description: "A minimal sensor with empty schema",
      schema: Zoi.object(%{}, coerce: true)

    @impl Jido.Sensor
    def init(_config, _context) do
      {:ok, %{initialized: true}}
    end

    @impl Jido.Sensor
    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule FailingInitSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "failing_init_sensor",
      description: "A sensor that fails to initialize",
      schema: Zoi.object(%{}, coerce: true)

    @impl Jido.Sensor
    def init(_config, _context) do
      {:error, :init_failed}
    end

    @impl Jido.Sensor
    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule RequiredFieldSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "required_field_sensor",
      description: "A sensor with required schema fields",
      schema:
        Zoi.object(
          %{
            required_field: Zoi.string()
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, _context) do
      {:ok, %{field: config.required_field}}
    end

    @impl Jido.Sensor
    def handle_event(_event, state) do
      {:ok, state}
    end
  end

  defmodule ReschedulingSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "rescheduling_sensor",
      description: "A sensor that reschedules itself",
      schema:
        Zoi.object(
          %{
            interval: Zoi.integer() |> Zoi.default(30)
          },
          coerce: true
        )

    @impl Jido.Sensor
    def init(config, context) do
      interval = config.interval

      state = %{
        interval: interval,
        context: context,
        tick_count: 0
      }

      {:ok, state, [{:schedule, interval}]}
    end

    @impl Jido.Sensor
    def handle_event(:tick, state) do
      signal =
        Jido.Signal.new!(%{
          source: "/sensor/rescheduling",
          type: "sensor.tick",
          data: %{tick: state.tick_count + 1}
        })

      new_state = %{state | tick_count: state.tick_count + 1}
      {:ok, new_state, [{:emit, signal}, {:schedule, state.interval}]}
    end
  end

  describe "start_link/1" do
    test "starts the runtime successfully with valid config" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "test"},
          context: %{agent_ref: self()}
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with minimal options" do
      {:ok, pid} = Runtime.start_link(sensor: MinimalSensor)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with keyword list options" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: [prefix: "keyword_test"],
          context: %{agent_ref: self()}
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with map options" do
      {:ok, pid} =
        Runtime.start_link(%{
          sensor: SimpleSensor,
          config: %{prefix: "map_test"},
          context: %{agent_ref: self()}
        })

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "fails when sensor module is missing" do
      Process.flag(:trap_exit, true)

      {:error, {:missing_required_option, :sensor}} = Runtime.start_link(config: %{})
    end

    test "fails when sensor init returns error" do
      Process.flag(:trap_exit, true)

      {:error, :init_failed} =
        Runtime.start_link(
          sensor: FailingInitSensor,
          context: %{agent_ref: self()}
        )
    end

    test "fails with invalid config schema" do
      Process.flag(:trap_exit, true)

      {:error, _reason} =
        Runtime.start_link(
          sensor: RequiredFieldSensor,
          config: %{}
        )
    end
  end

  describe "init callback" do
    test "calls sensor.init/2 on start" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: MinimalSensor,
          context: %{agent_ref: self()}
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "passes validated config to sensor.init/2" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "custom_prefix"},
          context: %{agent_ref: self()}
        )

      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "applies initial directives from init/2" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SchedulingSensor,
          config: %{interval: 50},
          context: %{agent_ref: self()}
        )

      assert Process.alive?(pid)

      assert_receive {:signal, signal}, 200
      assert signal.type == "sensor.tick"
      assert signal.data.tick == 1

      GenServer.stop(pid)
    end
  end

  describe "event/2" do
    test "injects events into the sensor" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "event_test"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, {:data, 42})

      assert_receive {:signal, signal}, 100
      assert signal.type == "event_test.data.received"
      assert signal.data.value == 42
      assert signal.data.count == 1

      GenServer.stop(pid)
    end

    test "injects multiple events in sequence" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "multi"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, {:data, 1})
      :ok = Runtime.event(pid, {:data, 2})
      :ok = Runtime.event(pid, {:data, 3})

      assert_receive {:signal, signal1}, 100
      assert signal1.data.value == 1
      assert signal1.data.count == 1

      assert_receive {:signal, signal2}, 100
      assert signal2.data.value == 2
      assert signal2.data.count == 2

      assert_receive {:signal, signal3}, 100
      assert signal3.data.value == 3
      assert signal3.data.count == 3

      GenServer.stop(pid)
    end

    test "handles events that produce no signals" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "noop"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, :noop)

      refute_receive {:signal, _}, 50

      GenServer.stop(pid)
    end

    test "handles events that return errors gracefully" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "error"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, {:error, :something_wrong})

      refute_receive {:signal, _}, 50
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "timer-based events" do
    test "schedules and receives tick events" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SchedulingSensor,
          config: %{interval: 30},
          context: %{agent_ref: self()}
        )

      assert_receive {:signal, signal}, 200
      assert signal.type == "sensor.tick"
      assert signal.data.tick == 1

      GenServer.stop(pid)
    end

    test "schedules custom events with payload" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: CustomEventSchedulingSensor,
          config: %{interval: 30},
          context: %{agent_ref: self()}
        )

      assert_receive {:signal, signal}, 200
      assert signal.type == "sensor.custom_event"
      assert signal.data.count == 1

      GenServer.stop(pid)
    end

    test "reschedules events from handle_event" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: ReschedulingSensor,
          config: %{interval: 25},
          context: %{agent_ref: self()}
        )

      assert_receive {:signal, signal1}, 200
      assert signal1.data.tick == 1

      assert_receive {:signal, signal2}, 200
      assert signal2.data.tick == 2

      assert_receive {:signal, signal3}, 200
      assert signal3.data.tick == 3

      GenServer.stop(pid)
    end
  end

  describe "signal delivery to pid" do
    test "sends signals to agent_ref pid via send/2" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "delivery"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, {:data, "test_value"})

      assert_receive {:signal, signal}, 100
      assert %Jido.Signal{} = signal

      GenServer.stop(pid)
    end

    test "signal has correct structure" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "structure"},
          context: %{agent_ref: self()}
        )

      :ok = Runtime.event(pid, {:data, 123})

      assert_receive {:signal, signal}, 100

      assert signal.type == "structure.data.received"
      assert signal.source == "/sensor/structure"
      assert signal.data.value == 123
      assert signal.data.count == 1

      GenServer.stop(pid)
    end

    test "does not crash when agent_ref is nil" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: SimpleSensor,
          config: %{prefix: "no_agent"},
          context: %{}
        )

      :ok = Runtime.event(pid, {:data, "ignored"})

      Process.sleep(50)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "child_spec/1" do
    test "returns valid child spec with default id" do
      spec = Runtime.child_spec(sensor: SimpleSensor)

      assert spec.id == Runtime
      assert spec.start == {Runtime, :start_link, [[sensor: SimpleSensor]]}
      assert spec.shutdown == 5_000
      assert spec.restart == :permanent
      assert spec.type == :worker
    end

    test "uses custom id when provided" do
      spec = Runtime.child_spec(sensor: SimpleSensor, id: :custom_sensor_id)

      assert spec.id == :custom_sensor_id
    end
  end

  describe "Jido.Sensors.Heartbeat integration" do
    test "emits heartbeat signals and reschedules" do
      {:ok, pid} =
        Runtime.start_link(
          sensor: Jido.Sensors.Heartbeat,
          config: %{interval: 30, message: "test_heartbeat"},
          context: %{agent_ref: self()}
        )

      assert_receive {:signal, signal1}, 200
      assert signal1.type == "jido.sensor.heartbeat"
      assert signal1.data.message == "test_heartbeat"

      # Verify rescheduling works
      assert_receive {:signal, signal2}, 200
      assert signal2.type == "jido.sensor.heartbeat"

      GenServer.stop(pid)
    end
  end
end
