defmodule JidoTest.BusSensorTest do
  use ExUnit.Case, async: true
  alias Jido.Sensors.BusSensor

  @moduletag :capture_log

  import ExUnit.CaptureLog

  @moduletag :skip

  setup do
    bus_name = :"bus_#{:erlang.unique_integer()}"
    start_supervised!({Jido.Bus, name: bus_name, adapter: :in_memory})
    start_supervised!({Phoenix.PubSub, name: TestPubSub})
    %{bus: bus_name}
  end

  describe "BusSensor" do
    test "initializes with required options", %{bus: bus} do
      opts = [
        pubsub: TestPubSub,
        bus_name: bus,
        stream_id: "test_stream",
        subscription_name: "test_subscription"
      ]

      {:ok, pid} = BusSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.bus_name == bus
      assert state.stream_id == "test_stream"
      assert is_pid(state.subscription)
    end

    test "handles bus signals with acknowledgment", %{bus: bus} do
      opts = [
        pubsub: TestPubSub,
        bus_name: bus,
        stream_id: "test_stream",
        subscription_name: "test_subscription"
      ]

      {:ok, pid} = BusSensor.start_link(opts)
      state = :sys.get_state(pid)
      Phoenix.PubSub.subscribe(TestPubSub, state.topic)

      test_signal = %{
        type: "test",
        data: %{value: 123}
      }

      send(pid, {:signal, test_signal})

      assert_receive {:sensor_signal, signal}, 1000
      assert signal.subject == "bus_event"
      assert signal.type == "bus"
      assert signal.data.stream_id == "test_stream"
      assert signal.data.signal == test_signal

      # Wait a bit to ensure the acknowledgment is processed
      Process.sleep(100)
    end

    test "supports custom concurrency and partitioning", %{bus: bus} do
      partition_by = fn signal -> signal.data.value end

      opts = [
        pubsub: TestPubSub,
        bus_name: bus,
        stream_id: "test_stream",
        subscription_name: "test_subscription",
        concurrency: 2,
        partition_by: partition_by
      ]

      {:ok, pid} = BusSensor.start_link(opts)
      state = :sys.get_state(pid)

      assert state.concurrency == 2
      assert state.partition_by == partition_by
    end

    test "logs warning on signal generation error", %{bus: bus} do
      defmodule ErrorBusSensor do
        @moduledoc false
        use Jido.Sensor,
          name: "error_bus_sensor",
          schema: [
            bus_name: [type: :atom, required: true],
            stream_id: [type: :string, required: true],
            subscription_name: [type: :string, required: true]
          ]

        def mount(opts), do: {:ok, opts}

        def generate_signal(_, _), do: {:error, :test_error}

        def handle_info({:signal, signal}, state) do
          case generate_signal(state, signal) do
            {:ok, sensor_signal} ->
              publish_signal(sensor_signal, state)
              :ok = Jido.Bus.ack(state.bus_name, state.subscription, signal)
              {:noreply, state}

            {:error, reason} ->
              Logger.warning("Error generating signal: #{inspect(reason)}")
              {:noreply, state}
          end
        end
      end

      opts = [
        pubsub: TestPubSub,
        bus_name: bus,
        stream_id: "test_stream",
        subscription_name: "test_subscription"
      ]

      {:ok, pid} = ErrorBusSensor.start_link(opts)

      log =
        capture_log(fn ->
          send(pid, {:signal, %{type: "test"}})
          Process.sleep(100)
        end)

      assert log =~ "Error generating signal: :test_error"
    end

    test "unsubscribes from bus on shutdown", %{bus: bus} do
      opts = [
        pubsub: TestPubSub,
        bus_name: bus,
        stream_id: "test_stream",
        subscription_name: "test_subscription"
      ]

      {:ok, pid} = BusSensor.start_link(opts)

      state = :sys.get_state(pid)
      subscription = state.subscription

      GenServer.stop(pid)

      # Verify subscription is removed
      assert {:error, :not_found} = Jido.Bus.unsubscribe(bus, subscription)
    end
  end
end
