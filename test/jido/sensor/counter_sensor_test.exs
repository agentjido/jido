defmodule JidoTest.SensorCounterTest do
  use JidoTest.Case, async: true
  alias JidoTest.TestSensors.CounterSensor

  @moduletag :capture_log

  import ExUnit.CaptureLog

  setup do
    {:ok, test_pid: self()}
  end

  describe "CounterSensor" do
    test "initializes with correct default values", %{test_pid: test_pid} do
      opts = [
        id: "test_counter",
        target: {:pid, target: test_pid},
        emit_interval: 1000
      ]

      {:ok, pid} = CounterSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.config.floor == 0
      assert state.counter == 0
      assert state.config.emit_interval == 1000
    end

    test "initializes with custom floor value", %{test_pid: test_pid} do
      opts = [
        id: "test_counter",
        target: {:pid, target: test_pid},
        emit_interval: 1000,
        floor: 10
      ]

      {:ok, pid} = CounterSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.config.floor == 10
      assert state.counter == 10
    end

    test "emits signals at specified interval", %{test_pid: test_pid} do
      opts = [
        id: "test_counter",
        target: {:pid, target: test_pid},
        emit_interval: 100,
        floor: 5
      ]

      {:ok, _pid} = CounterSensor.start_link(opts)

      # Wait for three emissions
      assert_receive {:signal, signal}, 200
      assert signal.type == "counter"
      assert signal.data.value == 6

      assert_receive {:signal, signal}, 200
      assert signal.type == "counter"
      assert signal.data.value == 7

      assert_receive {:signal, signal}, 200
      assert signal.type == "counter"
      assert signal.data.value == 8
    end

    test "handles errors in generate_signal", %{test_pid: test_pid} do
      defmodule ErrorCounterSensor do
        @moduledoc false
        use Jido.Sensor,
          name: "error_counter_sensor",
          schema: [
            emit_interval: [type: :pos_integer, required: true]
          ]

        @impl true
        def mount(opts) do
          state = %{
            id: opts.id,
            target: opts.target,
            config: %{
              emit_interval: opts.emit_interval
            }
          }

          schedule_emit(state)
          {:ok, state}
        end

        @impl true
        def deliver_signal(_state) do
          Logger.warning("Error generating signal: :test_error")
          {:error, :test_error}
        end

        @impl GenServer
        def handle_info(:emit, state) do
          case deliver_signal(state) do
            {:ok, signal} ->
              case Jido.Signal.Dispatch.dispatch(signal, state.target) do
                :ok ->
                  schedule_emit(state)
                  {:noreply, state}

                {:error, reason} ->
                  Logger.warning("Error dispatching signal: #{inspect(reason)}")
                  schedule_emit(state)
                  {:noreply, state}
              end

            {:error, reason} ->
              Logger.warning("Error generating signal: #{inspect(reason)}")
              schedule_emit(state)
              {:noreply, state}
          end
        end

        defp schedule_emit(state) do
          Process.send_after(self(), :emit, state.config.emit_interval)
        end
      end

      opts = [
        id: "test_counter",
        target: {:pid, target: test_pid},
        emit_interval: 100
      ]

      {:ok, _pid} = ErrorCounterSensor.start_link(opts)

      log =
        capture_log(fn ->
          # Wait for two emission attempts
          Process.sleep(250)
        end)

      assert log =~ "Error generating signal: :test_error"
    end
  end
end
