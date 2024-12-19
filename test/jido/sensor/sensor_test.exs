defmodule JidoTest.SensorTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  defmodule TestSensor do
    @moduledoc false
    use Jido.Sensor,
      name: "test_sensor",
      description: "A sensor for testing",
      category: :test,
      tags: [:test, :unit],
      vsn: "1.0.0",
      schema: [
        test_param: [type: :integer, default: 0]
      ]

    def mount(opts) do
      {:ok, Map.put(opts, :mounted, true)}
    end

    def generate_signal(state) do
      Jido.Signal.new(%{
        source: "#{state.sensor.name}:#{state.id}",
        subject: "test_signal",
        type: "test_signal",
        data: %{value: state.test_param},
        timestamp: DateTime.utc_now()
      })
    end

    def before_publish(signal, _state) do
      if signal.data.value >= 0 do
        {:ok, signal}
      else
        {:error, :invalid_value}
      end
    end
  end

  setup do
    start_supervised!({Phoenix.PubSub, name: SensorTestPubSub})
    :ok
  end

  describe "Sensor initialization" do
    test "starts the sensor with valid options" do
      opts = [
        id: "test_id",
        topic: "test_topic",
        pubsub: SensorTestPubSub,
        test_param: 42
      ]

      assert {:ok, pid} = TestSensor.start_link(opts)
      assert Process.alive?(pid)

      state = :sys.get_state(pid)
      assert state.id == "test_id"
      assert state.topic == "test_topic"
      assert state.pubsub == SensorTestPubSub
      assert state.test_param == 42
      assert state.mounted == true
    end

    test "uses default values when not provided" do
      opts = [pubsub: SensorTestPubSub]

      assert {:ok, pid} = TestSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert is_binary(state.id)
      assert state.topic =~ "test_sensor:"
      assert state.test_param == 0
      assert state.heartbeat_interval == 10_000
      assert state.retain_last == 10
    end

    test "fails to start with invalid options" do
      opts = [pubsub: SensorTestPubSub, test_param: "not an integer"]
      assert {:error, reason} = TestSensor.start_link(opts)
      assert reason =~ "Invalid parameters for Sensor"
    end

    test "fails to start without required pubsub option" do
      assert {:error, reason} = TestSensor.start_link([])
      assert reason =~ "Invalid parameters for Sensor"
      assert reason =~ "pubsub"
    end
  end

  describe "Sensor behavior" do
    setup do
      opts = [pubsub: SensorTestPubSub, test_param: 42]
      {:ok, pid} = TestSensor.start_link(opts)
      %{pid: pid}
    end

    test "generates and publishes signals", %{pid: pid} do
      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(SensorTestPubSub, state.topic)

      send(pid, :heartbeat)

      assert_receive {:sensor_signal, %Jido.Signal{subject: "test_signal", data: %{value: 42}}},
                     1000
    end

    test "retains last values", %{pid: pid} do
      Enum.each(1..15, fn i ->
        signal = %Jido.Signal{
          id: Jido.Util.generate_id(),
          source: "test_sensor",
          type: "test.signal",
          subject: "test_signal",
          data: %{value: i}
        }

        send(pid, {:sensor_signal, signal})
      end)

      last_values = TestSensor.get_last_values(pid)

      assert length(last_values) == 10
      assert Enum.map(last_values, & &1.data.value) == Enum.to_list(6..15)
    end

    test "validates signals before publishing", %{pid: pid} do
      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(SensorTestPubSub, state.topic)

      send(pid, :heartbeat)
      assert_receive {:sensor_signal, %Jido.Signal{data: %{value: 42}}}, 1000

      :sys.replace_state(pid, fn state -> %{state | test_param: -1} end)
      send(pid, :heartbeat)
      refute_receive {:sensor_signal, _}, 1000
    end

    test "handles custom heartbeat interval" do
      opts = [pubsub: SensorTestPubSub, heartbeat_interval: 100]
      {:ok, pid} = TestSensor.start_link(opts)

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(SensorTestPubSub, state.topic)

      # Increased the timeout to 300ms to account for potential delays
      assert_receive {:sensor_signal, %Jido.Signal{}}, 300
    end

    test "disables heartbeat when interval is 0" do
      opts = [pubsub: SensorTestPubSub, heartbeat_interval: 0]
      {:ok, pid} = TestSensor.start_link(opts)

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(SensorTestPubSub, state.topic)

      refute_receive {:sensor_signal, %Jido.Signal{}}, 1000
    end
  end

  describe "Error handling" do
    test "handles invalid runtime options" do
      opts = [pubsub: SensorTestPubSub, test_param: "not an integer"]
      assert {:error, reason} = TestSensor.start_link(opts)
      assert reason =~ "Invalid parameters for Sensor"
    end

    test "fails to start without required pubsub option" do
      assert {:error, reason} = TestSensor.start_link([])
      assert reason =~ "Invalid parameters for Sensor"
      assert reason =~ "required :pubsub option not found"
    end

    test "handles errors in generate_signal" do
      defmodule ErrorSensor1 do
        @moduledoc false
        use Jido.Sensor, name: "error_sensor"

        def generate_signal(_), do: {:error, :test_error}
      end

      {:ok, pid} = ErrorSensor1.start_link(pubsub: SensorTestPubSub)
      Phoenix.PubSub.subscribe(SensorTestPubSub, "error_sensor:#{:sys.get_state(pid).id}")

      log =
        capture_log(fn ->
          send(pid, :heartbeat)
          refute_receive {:sensor_signal, _}, 1000
        end)

      assert log =~ "Error generating or publishing signal: :test_error"
    end

    test "handles errors in before_publish" do
      defmodule ErrorSensor2 do
        @moduledoc false
        use Jido.Sensor, name: "error_sensor"

        def before_publish(_, _), do: {:error, :test_error}
      end

      {:ok, pid} = ErrorSensor2.start_link(pubsub: SensorTestPubSub)
      Phoenix.PubSub.subscribe(SensorTestPubSub, "error_sensor:#{:sys.get_state(pid).id}")

      log =
        capture_log(fn ->
          send(pid, :heartbeat)
          refute_receive {:sensor_signal, _}, 1000
        end)

      assert log =~ "Error generating or publishing signal: :test_error"
    end
  end

  describe "Sensor metadata" do
    test "returns correct metadata" do
      metadata = TestSensor.metadata()
      assert metadata.name == "test_sensor"
      assert metadata.description == "A sensor for testing"
      assert metadata.category == :test
      assert metadata.tags == [:test, :unit]
      assert metadata.vsn == "1.0.0"
      assert is_list(metadata.schema)
    end

    test "converts metadata to JSON-compatible format" do
      json = TestSensor.to_json()
      assert is_map(json)
      assert json.name == "test_sensor"
      assert json.category == "test"
      assert json.tags == ["test", "unit"]
    end
  end
end
