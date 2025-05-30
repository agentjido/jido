defmodule Jido.Signal.BusComprehensiveE2ETest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Signal.Bus

  @moduletag :capture_log
  # Increase timeout for this long-running test
  @moduletag timeout: 30_000

  defmodule TestClient do
    use GenServer
    require Logger

    def start_link(opts) do
      name = Keyword.get(opts, :name)

      if name,
        do: GenServer.start_link(__MODULE__, opts, name: name),
        else: GenServer.start_link(__MODULE__, opts)
    end

    def get_signals(pid) do
      GenServer.call(pid, :get_signals)
    end

    def clear_signals(pid) do
      GenServer.call(pid, :clear_signals)
    end

    def stop(pid) do
      GenServer.stop(pid)
    end

    @impl true
    def init(opts) do
      Logger.debug(
        "TestClient #{Keyword.fetch!(opts, :id)} initialized with name: #{Keyword.get(opts, :name)}"
      )

      {:ok,
       %{
         id: Keyword.fetch!(opts, :id),
         name: Keyword.get(opts, :name),
         signals: []
       }}
    end

    @impl true
    def handle_call(:get_signals, _from, state) do
      Logger.debug(
        "TestClient #{state.id} (#{state.name}) returning #{length(state.signals)} signals"
      )

      {:reply, state.signals, state}
    end

    @impl true
    def handle_call(:clear_signals, _from, state) do
      Logger.debug("TestClient #{state.id} (#{state.name}) cleared signals")
      {:reply, :ok, %{state | signals: []}}
    end

    @impl true
    def handle_info({:signal, signal}, state) do
      Logger.debug("TestClient #{state.id} (#{state.name}) received signal: #{signal.type}")
      {:noreply, %{state | signals: [signal | state.signals]}}
    end

    @impl true
    def handle_info(:stop, state) do
      Logger.debug("TestClient #{state.id} (#{state.name}) stopping")
      {:stop, :normal, state}
    end
  end

  describe "comprehensive E2E bus testing" do
    test "complete bus lifecycle with all features" do
      # ===== SETUP =====
      Logger.info("Starting comprehensive bus E2E test")

      # Start a bus with a unique name
      bus_name = "e2e_comprehensive_bus_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Bus, name: bus_name})

      # Wait for bus to be registered
      Process.sleep(50)

      # Get the bus PID
      {:ok, bus_pid} = Bus.whereis(bus_name)
      assert is_pid(bus_pid), "Bus should be running as a process"

      # ===== TEST 1: BUS STARTUP AND INITIALIZATION =====
      Logger.info("Testing bus startup and initialization")

      # Verify bus is alive and responding
      assert Process.alive?(bus_pid), "Bus process should be alive"

      # Test whereis functionality
      {:ok, found_pid} = Bus.whereis(bus_name)
      assert found_pid == bus_pid, "whereis should return the correct bus PID"

      # Test error case for non-existent bus
      assert {:error, :not_found} = Bus.whereis("non-existent-bus")

      # ===== TEST 2: SUBSCRIPTION MANAGEMENT =====
      Logger.info("Testing subscription management")

      # Create test client for regular subscription
      {:ok, regular_client} = TestClient.start_link(id: "regular_client")

      # Test regular subscription
      {:ok, regular_sub_id} =
        Bus.subscribe(bus_pid, "test.regular",
          dispatch: {:pid, target: regular_client, delivery_mode: :async}
        )

      assert is_binary(regular_sub_id), "Subscribe should return a subscription ID"

      # Create test client for persistent subscription
      {:ok, persistent_client} = TestClient.start_link(id: "persistent_client")

      # Test persistent subscription
      {:ok, persistent_sub_id} =
        Bus.subscribe(bus_pid, "test.persistent",
          dispatch: {:pid, target: persistent_client, delivery_mode: :async},
          persistent?: true
        )

      assert is_binary(persistent_sub_id), "Persistent subscribe should return a subscription ID"

      # Verify persistent subscription has a persistence process
      bus_state = :sys.get_state(bus_pid)
      persistent_subscription = bus_state.subscriptions[persistent_sub_id]
      assert persistent_subscription.persistent? == true
      assert is_pid(persistent_subscription.persistence_pid)
      assert Process.alive?(persistent_subscription.persistence_pid)

      # Test wildcard subscription
      {:ok, wildcard_client} = TestClient.start_link(id: "wildcard_client")

      {:ok, wildcard_sub_id} =
        Bus.subscribe(bus_pid, "**",
          dispatch: {:pid, target: wildcard_client, delivery_mode: :async}
        )

      # Test error case - duplicate subscription ID
      {:ok, duplicate_client} = TestClient.start_link(id: "duplicate_client")

      assert {:error, _} =
               Bus.subscribe(bus_pid, "test.duplicate",
                 subscription_id: regular_sub_id,
                 dispatch: {:pid, target: duplicate_client, delivery_mode: :async}
               )

      # ===== TEST 3: SIGNAL PUBLISHING AND ROUTING =====
      Logger.info("Testing signal publishing and routing")

      # Create test signals
      {:ok, regular_signal} =
        Signal.new(%{
          type: "test.regular",
          source: "/e2e_test",
          data: %{message: "regular signal", batch: 1}
        })

      {:ok, persistent_signal} =
        Signal.new(%{
          type: "test.persistent",
          source: "/e2e_test",
          data: %{message: "persistent signal", batch: 1}
        })

      {:ok, wildcard_signal} =
        Signal.new(%{
          type: "test.wildcard.signal",
          source: "/e2e_test",
          data: %{message: "wildcard signal", batch: 1}
        })

      # Publish signals
      {:ok, recorded_signals} =
        Bus.publish(bus_pid, [regular_signal, persistent_signal, wildcard_signal])

      assert length(recorded_signals) == 3, "Should return 3 recorded signals"

      # Verify all recorded signals have proper structure
      Enum.each(recorded_signals, fn recorded ->
        assert Map.has_key?(recorded, :id)
        assert Map.has_key?(recorded, :type)
        assert Map.has_key?(recorded, :created_at)
        assert Map.has_key?(recorded, :signal)
      end)

      # Give time for signal delivery
      Process.sleep(200)

      # Verify signal delivery
      regular_signals = TestClient.get_signals(regular_client)
      assert length(regular_signals) == 1, "Regular client should receive 1 signal"
      assert hd(regular_signals).type == "test.regular"

      persistent_signals = TestClient.get_signals(persistent_client)
      assert length(persistent_signals) == 1, "Persistent client should receive 1 signal"
      assert hd(persistent_signals).type == "test.persistent"

      wildcard_signals = TestClient.get_signals(wildcard_client)
      assert length(wildcard_signals) == 3, "Wildcard client should receive all 3 signals"

      # Test empty publish
      {:ok, empty_recorded} = Bus.publish(bus_pid, [])
      assert empty_recorded == [], "Empty publish should return empty list"

      # Test invalid signal publish
      assert {:error, _} = Bus.publish(bus_pid, [%{not_a_signal: true}])

      # ===== TEST 4: ACKNOWLEDGMENT FOR PERSISTENT SUBSCRIPTIONS =====
      Logger.info("Testing acknowledgment for persistent subscriptions")

      # Test acknowledgment for persistent subscription
      first_recorded = hd(recorded_signals)
      assert :ok = Bus.ack(bus_pid, persistent_sub_id, first_recorded.id)

      # Test error cases for ack
      assert {:error, _} = Bus.ack(bus_pid, "non-existent-sub", "signal-id")
      # non-persistent
      assert {:error, _} = Bus.ack(bus_pid, regular_sub_id, "signal-id")

      # ===== TEST 5: REPLAY FUNCTIONALITY =====
      Logger.info("Testing replay functionality")

      # Test replay all signals
      {:ok, all_replayed} = Bus.replay(bus_pid, "**")
      assert length(all_replayed) == 3, "Should replay all 3 signals"

      # Test replay with specific path
      {:ok, regular_replayed} = Bus.replay(bus_pid, "test.regular")
      assert length(regular_replayed) == 1, "Should replay 1 regular signal"
      assert hd(regular_replayed).signal.type == "test.regular"

      # Test replay with timestamp (replay from beginning)
      {:ok, timestamped_replayed} = Bus.replay(bus_pid, "**", 0)
      assert length(timestamped_replayed) >= 3, "Should replay signals from timestamp 0"

      # Test replay with no matches
      {:ok, no_matches} = Bus.replay(bus_pid, "non.existent.pattern")
      assert length(no_matches) == 0, "Should return empty list for non-matching pattern"

      # ===== TEST 6: SNAPSHOT OPERATIONS =====
      Logger.info("Testing snapshot operations")

      # Test snapshot creation
      {:ok, snapshot1} = Bus.snapshot_create(bus_pid, "test.regular")
      assert Map.has_key?(snapshot1, :id)
      assert Map.has_key?(snapshot1, :path)
      assert snapshot1.path == "test.regular"

      {:ok, snapshot2} = Bus.snapshot_create(bus_pid, "test.**")
      assert snapshot2.path == "test.**"

      # Test snapshot listing
      snapshots = Bus.snapshot_list(bus_pid)
      assert length(snapshots) >= 2, "Should have at least 2 snapshots"
      assert Enum.any?(snapshots, &(&1.id == snapshot1.id))
      assert Enum.any?(snapshots, &(&1.id == snapshot2.id))

      # Test snapshot reading
      {:ok, read_snapshot1} = Bus.snapshot_read(bus_pid, snapshot1.id)
      assert Map.has_key?(read_snapshot1, :signals)
      assert Map.has_key?(read_snapshot1, :path)
      assert read_snapshot1.path == "test.regular"

      {:ok, read_snapshot2} = Bus.snapshot_read(bus_pid, snapshot2.id)
      assert map_size(read_snapshot2.signals) >= 2, "test.** should match multiple signals"

      # Test error cases for snapshot operations
      assert {:error, :not_found} = Bus.snapshot_read(bus_pid, "non-existent-snapshot")

      # Test snapshot deletion
      assert :ok = Bus.snapshot_delete(bus_pid, snapshot1.id)
      assert {:error, :not_found} = Bus.snapshot_read(bus_pid, snapshot1.id)
      assert {:error, :not_found} = Bus.snapshot_delete(bus_pid, "non-existent-snapshot")

      # ===== TEST 7: DISCONNECTION AND RECONNECTION =====
      Logger.info("Testing disconnection and reconnection")

      # Create a new persistent client for reconnection testing
      {:ok, reconnect_client} = TestClient.start_link(id: "reconnect_client")

      {:ok, reconnect_sub_id} =
        Bus.subscribe(bus_pid, "test.reconnect",
          dispatch: {:pid, target: reconnect_client, delivery_mode: :async},
          persistent?: true
        )

      # Publish a signal to the reconnect subscription
      {:ok, reconnect_signal} =
        Signal.new(%{
          type: "test.reconnect",
          source: "/e2e_test",
          data: %{message: "before disconnect", batch: 2}
        })

      {:ok, _} = Bus.publish(bus_pid, [reconnect_signal])
      Process.sleep(100)

      # Verify signal was received
      reconnect_signals = TestClient.get_signals(reconnect_client)
      assert length(reconnect_signals) == 1

      # Simulate disconnection by stopping the client
      TestClient.stop(reconnect_client)
      Process.sleep(100)

      # Publish more signals while disconnected
      {:ok, disconnected_signal} =
        Signal.new(%{
          type: "test.reconnect",
          source: "/e2e_test",
          data: %{message: "while disconnected", batch: 3}
        })

      {:ok, _} = Bus.publish(bus_pid, [disconnected_signal])
      Process.sleep(100)

      # Create new client and reconnect
      {:ok, new_reconnect_client} = TestClient.start_link(id: "new_reconnect_client")
      {:ok, checkpoint} = Bus.reconnect(bus_pid, reconnect_sub_id, new_reconnect_client)
      # The checkpoint can be either a timestamp string or integer (0 if no signals)
      assert (is_binary(checkpoint) and String.match?(checkpoint, ~r/\d{4}-\d{2}-\d{2}T/)) or
               checkpoint == 0,
             "Reconnect should return a timestamp string or 0"

      # Test error cases for reconnect
      assert {:error, :subscription_not_found} =
               Bus.reconnect(bus_pid, "non-existent-sub", self())

      # ===== TEST 8: UNSUBSCRIPTION =====
      Logger.info("Testing unsubscription")

      # Test regular unsubscription
      assert :ok = Bus.unsubscribe(bus_pid, regular_sub_id)

      # Test persistent unsubscription with delete_persistence
      persistence_pid_before = persistent_subscription.persistence_pid

      assert Process.alive?(persistence_pid_before),
             "Persistence process should be alive before unsubscribe"

      assert :ok = Bus.unsubscribe(bus_pid, persistent_sub_id, delete_persistence: true)

      # Verify the subscription is removed from the bus state
      updated_bus_state = :sys.get_state(bus_pid)

      refute Map.has_key?(updated_bus_state.subscriptions, persistent_sub_id),
             "Persistent subscription should be removed from bus state"

      # Test error case for non-existent subscription
      assert {:error, _} = Bus.unsubscribe(bus_pid, "non-existent-subscription")

      # ===== TEST 9: SIGNAL ORDER AND BATCHING =====
      Logger.info("Testing signal order and batching")

      # Create a client for order testing
      {:ok, order_client} = TestClient.start_link(id: "order_client")

      {:ok, order_sub_id} =
        Bus.subscribe(bus_pid, "test.order.**",
          dispatch: {:pid, target: order_client, delivery_mode: :async}
        )

      # Create multiple signals with different types
      ordered_signals =
        Enum.map(1..5, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.order.#{i}",
              source: "/e2e_test",
              data: %{sequence: i, batch: 4}
            })

          signal
        end)

      # Publish signals in batch
      {:ok, batch_recorded} = Bus.publish(bus_pid, ordered_signals)
      assert length(batch_recorded) == 5

      Process.sleep(200)

      # Verify all signals were received
      order_signals = TestClient.get_signals(order_client)
      assert length(order_signals) == 5

      # ===== TEST 10: MIDDLEWARE AND EDGE CASES =====
      Logger.info("Testing edge cases and error handling")

      # Test publish with correlation_id preservation
      {:ok, correlated_signal} =
        Signal.new(%{
          type: "test.correlation",
          source: "/e2e_test",
          data: %{correlation_test: true}
        })

      {:ok, _} = Bus.publish(bus_pid, [correlated_signal])

      # Test very large signal batches
      large_batch =
        Enum.map(1..100, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.large.batch",
              source: "/e2e_test",
              data: %{index: i, batch: 5}
            })

          signal
        end)

      {:ok, large_recorded} = Bus.publish(bus_pid, large_batch)
      assert length(large_recorded) == 100

      # ===== CLEANUP =====
      Logger.info("Cleaning up test resources")

      # Unsubscribe remaining subscriptions
      :ok = Bus.unsubscribe(bus_pid, wildcard_sub_id)
      :ok = Bus.unsubscribe(bus_pid, reconnect_sub_id)
      :ok = Bus.unsubscribe(bus_pid, order_sub_id)

      # Stop remaining test clients
      TestClient.stop(wildcard_client)
      TestClient.stop(new_reconnect_client)
      TestClient.stop(order_client)

      # Delete remaining snapshots
      remaining_snapshots = Bus.snapshot_list(bus_pid)

      Enum.each(remaining_snapshots, fn snapshot ->
        Bus.snapshot_delete(bus_pid, snapshot.id)
      end)

      Logger.info("Comprehensive E2E test completed successfully")
    end
  end

  describe "bus configuration and startup options" do
    test "bus starts with custom configuration" do
      Logger.info("Testing bus startup with custom configuration")

      bus_name = "config_test_bus_#{:erlang.unique_integer([:positive])}"

      # Test starting bus with middleware configuration
      custom_opts = [
        name: bus_name,
        middleware: [
          # Add middleware configurations here when available
        ]
      ]

      {:ok, bus_pid} = start_supervised({Bus, custom_opts})
      assert Process.alive?(bus_pid)

      {:ok, found_pid} = Bus.whereis(bus_name)
      assert found_pid == bus_pid
    end

    test "bus handles invalid startup options gracefully" do
      # Test missing name
      assert_raise KeyError, fn ->
        start_supervised({Bus, []})
      end
    end
  end

  describe "concurrent operations and stress testing" do
    test "handles concurrent subscriptions and publishing" do
      Logger.info("Testing concurrent operations")

      bus_name = "concurrent_test_bus_#{:erlang.unique_integer([:positive])}"
      {:ok, _} = start_supervised({Bus, name: bus_name})

      # Create multiple clients concurrently
      clients =
        Enum.map(1..10, fn i ->
          {:ok, client} = TestClient.start_link(id: "concurrent_client_#{i}")
          client
        end)

      # Subscribe all clients concurrently
      subscription_tasks =
        Enum.map(Enum.with_index(clients), fn {client, i} ->
          Task.async(fn ->
            Bus.subscribe(bus_name, "test.concurrent.#{rem(i, 3)}",
              dispatch: {:pid, target: client, delivery_mode: :async}
            )
          end)
        end)

      subscription_ids =
        subscription_tasks
        |> Enum.map(&Task.await/1)
        |> Enum.map(fn {:ok, id} -> id end)

      # Publish multiple signals concurrently
      publish_tasks =
        Enum.map(1..50, fn i ->
          Task.async(fn ->
            {:ok, signal} =
              Signal.new(%{
                type: "test.concurrent.#{rem(i, 3)}",
                source: "/concurrent_test",
                data: %{index: i}
              })

            Bus.publish(bus_name, [signal])
          end)
        end)

      # Wait for all publishes to complete
      Enum.each(publish_tasks, &Task.await/1)

      # Give time for signal delivery
      Process.sleep(500)

      # Verify signals were delivered
      total_signals =
        clients
        |> Enum.map(&TestClient.get_signals/1)
        |> Enum.map(&length/1)
        |> Enum.sum()

      assert total_signals > 0, "Should have delivered signals to clients"

      # Cleanup
      Enum.each(subscription_ids, fn id ->
        Bus.unsubscribe(bus_name, id)
      end)

      Enum.each(clients, &TestClient.stop/1)
    end
  end
end
