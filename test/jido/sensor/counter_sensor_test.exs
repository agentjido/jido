defmodule JidoTest.SensorCounterTest do
  use ExUnit.Case, async: true
  alias JidoTest.TestSensors.CounterSensor

  @moduletag :capture_log

  import ExUnit.CaptureLog

  setup do
    start_supervised!({Phoenix.PubSub, name: TestPubSub})
    :ok
  end

  describe "CounterSensor" do
    test "initializes with correct default values" do
      opts = [pubsub: TestPubSub, emit_interval: 1000]
      {:ok, pid} = CounterSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.floor == 0
      assert state.counter == 0
      assert state.emit_interval == 1000
    end

    test "initializes with custom floor value" do
      opts = [pubsub: TestPubSub, emit_interval: 1000, floor: 10]
      {:ok, pid} = CounterSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.floor == 10
      assert state.counter == 10
    end

    test "emits signals at specified interval" do
      opts = [pubsub: TestPubSub, emit_interval: 100, floor: 5]
      {:ok, pid} = CounterSensor.start_link(opts)

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      # Wait for three emissions
      assert_receive {:sensor_signal, %{data: %{value: 6}}}, 200
      assert_receive {:sensor_signal, %{data: %{value: 7}}}, 200
      assert_receive {:sensor_signal, %{data: %{value: 8}}}, 200
    end

    test "handles errors in generate_signal" do
      defmodule ErrorCounterSensor do
        @moduledoc false
        use Jido.Sensor,
          name: "error_counter_sensor",
          schema: [
            emit_interval: [type: :pos_integer, required: true]
          ]

        def mount(opts) do
          schedule_emit(opts)
          {:ok, opts}
        end

        def generate_signal(_), do: {:error, :test_error}

        def handle_info(:emit, state) do
          case generate_signal(state) do
            {:ok, signal, new_state} ->
              publish_signal(signal, new_state)
              schedule_emit(new_state)
              {:noreply, new_state}

            {:error, reason} ->
              Logger.warning("Error generating signal: #{inspect(reason)}")
              schedule_emit(state)
              {:noreply, state}
          end
        end

        defp schedule_emit(state) do
          Process.send_after(self(), :emit, state.emit_interval)
        end
      end

      opts = [pubsub: TestPubSub, emit_interval: 100]
      {:ok, pid} = ErrorCounterSensor.start_link(opts)

      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      log =
        capture_log(fn ->
          # Wait for two emission attempts
          Process.sleep(250)
        end)

      assert log =~ "Error generating signal: :test_error"
    end
  end
end
