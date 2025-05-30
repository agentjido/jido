defmodule Jido.Signal.BusMultiBusE2ETest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Signal.Bus

  @moduletag :capture_log
  @moduletag timeout: 30_000

  defmodule MultiTestClient do
    use GenServer
    require Logger

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def get_signals(pid) do
      GenServer.call(pid, :get_signals)
    end

    def get_signals_by_bus(pid, bus_name) do
      GenServer.call(pid, {:get_signals_by_bus, bus_name})
    end

    def clear_signals(pid) do
      GenServer.call(pid, :clear_signals)
    end

    def stop(pid) do
      GenServer.stop(pid)
    end

    @impl true
    def init(opts) do
      client_id = Keyword.fetch!(opts, :id)
      Logger.debug("MultiTestClient #{client_id} initialized")

      {:ok,
       %{
         id: client_id,
         signals: [],
         signals_by_bus: %{}
       }}
    end

    @impl true
    def handle_call(:get_signals, _from, state) do
      {:reply, state.signals, state}
    end

    @impl true
    def handle_call({:get_signals_by_bus, bus_name}, _from, state) do
      signals = Map.get(state.signals_by_bus, bus_name, [])
      {:reply, signals, state}
    end

    @impl true
    def handle_call(:clear_signals, _from, state) do
      {:reply, :ok, %{state | signals: [], signals_by_bus: %{}}}
    end

    @impl true
    def handle_info({:signal, signal}, state) do
      Logger.debug("MultiTestClient #{state.id} received signal: #{signal.type}")

      # Store signal globally and by bus
      new_signals = [signal | state.signals]

      # Extract bus info from metadata if available
      bus_name =
        case signal.jido_dispatch do
          %{bus_name: name} -> name
          _ -> :unknown_bus
        end

      bus_signals = Map.get(state.signals_by_bus, bus_name, [])
      new_signals_by_bus = Map.put(state.signals_by_bus, bus_name, [signal | bus_signals])

      {:noreply, %{state | signals: new_signals, signals_by_bus: new_signals_by_bus}}
    end

    @impl true
    def handle_info(:stop, state) do
      Logger.debug("MultiTestClient #{state.id} stopping")
      {:stop, :normal, state}
    end
  end

  # Custom middleware to tag signals with bus information
  defmodule BusTaggingMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      bus_name = Keyword.fetch!(opts, :bus_name)
      {:ok, %{bus_name: bus_name}}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      # Tag the signal with bus name in jido_dispatch metadata
      tagged_signal = %{
        signal
        | jido_dispatch: Map.merge(signal.jido_dispatch || %{}, %{bus_name: state.bus_name})
      }

      {:cont, tagged_signal, state}
    end
  end

  # Filtering middleware that can filter signals based on patterns
  defmodule FilteringMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      filter_pattern = Keyword.get(opts, :filter_pattern, nil)
      # :allow or :deny
      filter_mode = Keyword.get(opts, :filter_mode, :allow)
      {:ok, %{filter_pattern: filter_pattern, filter_mode: filter_mode}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      if state.filter_pattern do
        filtered_signals =
          case state.filter_mode do
            :allow ->
              Enum.filter(signals, fn signal ->
                String.contains?(signal.type, state.filter_pattern)
              end)

            :deny ->
              Enum.reject(signals, fn signal ->
                String.contains?(signal.type, state.filter_pattern)
              end)
          end

        {:cont, filtered_signals, state}
      else
        {:cont, signals, state}
      end
    end
  end

  # Metrics middleware for tracking signal counts
  defmodule MetricsMiddleware do
    use Jido.Signal.Bus.Middleware

    @impl true
    def init(opts) do
      test_pid = Keyword.get(opts, :test_pid)
      {:ok, %{publish_count: 0, dispatch_count: 0, test_pid: test_pid}}
    end

    @impl true
    def before_publish(signals, _context, state) do
      new_count = state.publish_count + length(signals)
      new_state = %{state | publish_count: new_count}

      if state.test_pid do
        send(state.test_pid, {:metrics, :publish_count, new_count})
      end

      {:cont, signals, new_state}
    end

    @impl true
    def before_dispatch(signal, _subscriber, _context, state) do
      new_count = state.dispatch_count + 1
      new_state = %{state | dispatch_count: new_count}

      if state.test_pid do
        send(state.test_pid, {:metrics, :dispatch_count, new_count})
      end

      {:cont, signal, new_state}
    end
  end

  describe "multi-bus signal partitioning and cross-bus subscriptions" do
    test "signals are properly partitioned between two buses" do
      Logger.info("Starting multi-bus E2E test")

      # Create two buses with different configurations
      bus_a_name = "bus_a_#{:erlang.unique_integer([:positive])}"
      bus_b_name = "bus_b_#{:erlang.unique_integer([:positive])}"

      # Bus A with filtering middleware (only allows "user.*" signals)
      {:ok, bus_a_pid} =
        start_supervised(
          {Bus,
           name: bus_a_name,
           middleware: [
             {BusTaggingMiddleware, bus_name: bus_a_name},
             {FilteringMiddleware, filter_pattern: "user.", filter_mode: :allow},
             {MetricsMiddleware, test_pid: self()}
           ]}
        )

      # Bus B with different filtering (only allows "system.*" signals)
      {:ok, bus_b_pid} =
        start_supervised(
          {Bus,
           name: bus_b_name,
           middleware: [
             {BusTaggingMiddleware, bus_name: bus_b_name},
             {FilteringMiddleware, filter_pattern: "system.", filter_mode: :allow},
             {MetricsMiddleware, test_pid: self()}
           ]}
        )

      # Wait for buses to be registered
      Process.sleep(100)

      # Verify both buses are running
      {:ok, found_bus_a} = Bus.whereis(bus_a_name)
      {:ok, found_bus_b} = Bus.whereis(bus_b_name)
      assert found_bus_a == bus_a_pid
      assert found_bus_b == bus_b_pid

      Logger.info("Both buses started successfully")

      # ===== CREATE CLIENTS WITH CROSS-BUS SUBSCRIPTIONS =====

      # Client 1: Subscribes to both buses for different signal types
      {:ok, client_1} = MultiTestClient.start_link(id: "cross_bus_client")

      # Subscribe to user signals on Bus A and system signals on Bus B
      {:ok, sub_1a} =
        Bus.subscribe(bus_a_pid, "user.**",
          dispatch: {:pid, target: client_1, delivery_mode: :async}
        )

      {:ok, sub_1b} =
        Bus.subscribe(bus_b_pid, "system.**",
          dispatch: {:pid, target: client_1, delivery_mode: :async}
        )

      # Client 2: Only subscribes to Bus A
      {:ok, client_2} = MultiTestClient.start_link(id: "bus_a_only_client")

      {:ok, sub_2a} =
        Bus.subscribe(bus_a_pid, "**", dispatch: {:pid, target: client_2, delivery_mode: :async})

      # Client 3: Only subscribes to Bus B
      {:ok, client_3} = MultiTestClient.start_link(id: "bus_b_only_client")

      {:ok, sub_3b} =
        Bus.subscribe(bus_b_pid, "**", dispatch: {:pid, target: client_3, delivery_mode: :async})

      Logger.info("All clients subscribed successfully")

      # ===== PUBLISH SIGNALS TO BOTH BUSES =====

      # Create test signals of different types
      {:ok, user_signal_1} =
        Signal.new(%{
          type: "user.login",
          source: "/auth",
          data: %{user_id: "user_123", timestamp: DateTime.utc_now()}
        })

      {:ok, user_signal_2} =
        Signal.new(%{
          type: "user.logout",
          source: "/auth",
          data: %{user_id: "user_456", timestamp: DateTime.utc_now()}
        })

      {:ok, system_signal_1} =
        Signal.new(%{
          type: "system.startup",
          source: "/server",
          data: %{service: "api", version: "1.0.0"}
        })

      {:ok, system_signal_2} =
        Signal.new(%{
          type: "system.health_check",
          source: "/monitor",
          data: %{status: "healthy", checks: 5}
        })

      {:ok, other_signal} =
        Signal.new(%{
          type: "data.created",
          source: "/database",
          data: %{table: "users", record_id: 789}
        })

      # Publish user signals to Bus A (should be allowed by filter)
      Logger.info("Publishing user signals to Bus A")
      {:ok, recorded_a1} = Bus.publish(bus_a_pid, [user_signal_1, user_signal_2])
      assert length(recorded_a1) == 2

      # Publish system signals to Bus A (should be filtered out)
      Logger.info("Publishing system signals to Bus A (should be filtered)")
      {:ok, recorded_a2} = Bus.publish(bus_a_pid, [system_signal_1, system_signal_2])
      assert length(recorded_a2) == 0, "System signals should be filtered out by Bus A"

      # Publish other signal to Bus A (should be filtered out)
      {:ok, recorded_a3} = Bus.publish(bus_a_pid, [other_signal])
      assert length(recorded_a3) == 0, "Other signal should be filtered out by Bus A"

      # Publish system signals to Bus B (should be allowed by filter)
      Logger.info("Publishing system signals to Bus B")
      {:ok, recorded_b1} = Bus.publish(bus_b_pid, [system_signal_1, system_signal_2])
      assert length(recorded_b1) == 2

      # Publish user signals to Bus B (should be filtered out)
      Logger.info("Publishing user signals to Bus B (should be filtered)")
      {:ok, recorded_b2} = Bus.publish(bus_b_pid, [user_signal_1, user_signal_2])
      assert length(recorded_b2) == 0, "User signals should be filtered out by Bus B"

      # Give time for signal delivery
      Process.sleep(300)

      # ===== VERIFY SIGNAL PARTITIONING =====

      # Check Client 1 (cross-bus subscriber)
      client_1_signals = MultiTestClient.get_signals(client_1)
      Logger.info("Client 1 received #{length(client_1_signals)} total signals")

      # Should receive user signals from Bus A and system signals from Bus B
      user_signals_received =
        Enum.filter(client_1_signals, fn signal -> String.starts_with?(signal.type, "user.") end)

      system_signals_received =
        Enum.filter(client_1_signals, fn signal -> String.starts_with?(signal.type, "system.") end)

      assert length(user_signals_received) == 2,
             "Client 1 should receive 2 user signals from Bus A"

      assert length(system_signals_received) == 2,
             "Client 1 should receive 2 system signals from Bus B"

      # Check Client 2 (Bus A only)
      client_2_signals = MultiTestClient.get_signals(client_2)
      Logger.info("Client 2 received #{length(client_2_signals)} signals from Bus A only")

      # Should only receive user signals (filtered by Bus A)
      assert length(client_2_signals) == 2, "Client 2 should receive 2 user signals from Bus A"

      Enum.each(client_2_signals, fn signal ->
        assert String.starts_with?(signal.type, "user."),
               "Client 2 should only receive user signals"
      end)

      # Check Client 3 (Bus B only)
      client_3_signals = MultiTestClient.get_signals(client_3)
      Logger.info("Client 3 received #{length(client_3_signals)} signals from Bus B only")

      # Should only receive system signals (filtered by Bus B)
      assert length(client_3_signals) == 2, "Client 3 should receive 2 system signals from Bus B"

      Enum.each(client_3_signals, fn signal ->
        assert String.starts_with?(signal.type, "system."),
               "Client 3 should only receive system signals"
      end)

      # ===== VERIFY MIDDLEWARE METRICS =====

      # Check that metrics middleware tracked publishes correctly
      # Bus A: 2 user signals published (others filtered out)
      assert_receive {:metrics, :publish_count, 2}, 1000
      # Bus B: 2 system signals published (others filtered out)
      assert_receive {:metrics, :publish_count, 2}, 1000

      # Check dispatch counts (should be higher due to multiple subscribers per bus)
      assert_receive {:metrics, :dispatch_count, _}, 1000
      assert_receive {:metrics, :dispatch_count, _}, 1000

      Logger.info("Middleware metrics verified")

      # ===== TEST BUS ISOLATION =====
      Logger.info("Testing bus isolation")

      # Snapshot operations should be isolated per bus
      {:ok, snapshot_a} = Bus.snapshot_create(bus_a_pid, "user.**")
      {:ok, snapshot_b} = Bus.snapshot_create(bus_b_pid, "system.**")

      {:ok, snapshot_a_data} = Bus.snapshot_read(bus_a_pid, snapshot_a.id)
      {:ok, snapshot_b_data} = Bus.snapshot_read(bus_b_pid, snapshot_b.id)

      assert map_size(snapshot_a_data.signals) == 2, "Bus A snapshot should have 2 user signals"
      assert map_size(snapshot_b_data.signals) == 2, "Bus B snapshot should have 2 system signals"

      # Replay should also be isolated
      {:ok, replay_a} = Bus.replay(bus_a_pid, "**")
      {:ok, replay_b} = Bus.replay(bus_b_pid, "**")

      assert length(replay_a) == 2, "Bus A should replay 2 signals"
      assert length(replay_b) == 2, "Bus B should replay 2 signals"

      # ===== TEST PERSISTENT SUBSCRIPTIONS ACROSS BUSES =====
      Logger.info("Testing persistent subscriptions across buses")

      {:ok, persistent_client} = MultiTestClient.start_link(id: "persistent_cross_bus_client")

      # Create persistent subscriptions on both buses
      {:ok, persistent_sub_a} =
        Bus.subscribe(bus_a_pid, "user.login",
          dispatch: {:pid, target: persistent_client, delivery_mode: :async},
          persistent?: true
        )

      {:ok, persistent_sub_b} =
        Bus.subscribe(bus_b_pid, "system.startup",
          dispatch: {:pid, target: persistent_client, delivery_mode: :async},
          persistent?: true
        )

      # Publish specific signals that match persistent subscriptions
      {:ok, login_signal} =
        Signal.new(%{
          type: "user.login",
          source: "/auth",
          data: %{user_id: "persistent_user", session_id: "abc123"}
        })

      {:ok, startup_signal} =
        Signal.new(%{
          type: "system.startup",
          source: "/server",
          data: %{service: "database", version: "2.0.0"}
        })

      {:ok, _} = Bus.publish(bus_a_pid, [login_signal])
      {:ok, _} = Bus.publish(bus_b_pid, [startup_signal])

      Process.sleep(200)

      # Verify persistent client received signals from both buses
      persistent_signals = MultiTestClient.get_signals(persistent_client)

      assert length(persistent_signals) == 2,
             "Persistent client should receive signals from both buses"

      # Test acknowledgment for persistent subscriptions
      [first_signal | _] = persistent_signals
      assert :ok = Bus.ack(bus_a_pid, persistent_sub_a, first_signal.id)

      # ===== CLEANUP =====
      Logger.info("Cleaning up test resources")

      # Unsubscribe all clients
      :ok = Bus.unsubscribe(bus_a_pid, sub_1a)
      :ok = Bus.unsubscribe(bus_b_pid, sub_1b)
      :ok = Bus.unsubscribe(bus_a_pid, sub_2a)
      :ok = Bus.unsubscribe(bus_b_pid, sub_3b)
      :ok = Bus.unsubscribe(bus_a_pid, persistent_sub_a)
      :ok = Bus.unsubscribe(bus_b_pid, persistent_sub_b)

      # Stop all clients
      MultiTestClient.stop(client_1)
      MultiTestClient.stop(client_2)
      MultiTestClient.stop(client_3)
      MultiTestClient.stop(persistent_client)

      # Clean up snapshots
      :ok = Bus.snapshot_delete(bus_a_pid, snapshot_a.id)
      :ok = Bus.snapshot_delete(bus_b_pid, snapshot_b.id)

      Logger.info("Multi-bus E2E test completed successfully")
    end
  end

  describe "middleware interaction between buses" do
    test "different middleware configurations work independently" do
      Logger.info("Testing independent middleware configurations")

      # Bus 1: Transformation middleware
      defmodule TransformMiddleware do
        use Jido.Signal.Bus.Middleware

        @impl true
        def init(opts) do
          prefix = Keyword.get(opts, :prefix, "transformed")
          {:ok, %{prefix: prefix}}
        end

        @impl true
        def before_publish(signals, _context, state) do
          transformed =
            Enum.map(signals, fn signal ->
              %{signal | type: "#{state.prefix}.#{signal.type}"}
            end)

          {:cont, transformed, state}
        end
      end

      # Bus 2: Enrichment middleware
      defmodule EnrichmentMiddleware do
        use Jido.Signal.Bus.Middleware

        @impl true
        def init(opts) do
          enrichment = Keyword.get(opts, :enrichment, %{})
          {:ok, %{enrichment: enrichment}}
        end

        @impl true
        def before_publish(signals, _context, state) do
          enriched =
            Enum.map(signals, fn signal ->
              enriched_data = Map.merge(signal.data, state.enrichment)
              %{signal | data: enriched_data}
            end)

          {:cont, enriched, state}
        end
      end

      bus_transform_name = "transform_bus_#{:erlang.unique_integer([:positive])}"
      bus_enrich_name = "enrich_bus_#{:erlang.unique_integer([:positive])}"

      {:ok, _} =
        start_supervised(
          {Bus,
           name: bus_transform_name,
           middleware: [
             {TransformMiddleware, prefix: "xformed"}
           ]}
        )

      {:ok, _} =
        start_supervised(
          {Bus,
           name: bus_enrich_name,
           middleware: [
             {EnrichmentMiddleware, enrichment: %{middleware: "enriched", timestamp: "added"}}
           ]}
        )

      # Create clients for each bus
      {:ok, transform_client} = MultiTestClient.start_link(id: "transform_client")
      {:ok, enrich_client} = MultiTestClient.start_link(id: "enrich_client")

      # Subscribe to both buses
      {:ok, _} =
        Bus.subscribe(bus_transform_name, "**",
          dispatch: {:pid, target: transform_client, delivery_mode: :async}
        )

      {:ok, _} =
        Bus.subscribe(bus_enrich_name, "**",
          dispatch: {:pid, target: enrich_client, delivery_mode: :async}
        )

      # Publish the same signal to both buses
      {:ok, test_signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{original: "data"}
        })

      {:ok, _} = Bus.publish(bus_transform_name, [test_signal])
      {:ok, _} = Bus.publish(bus_enrich_name, [test_signal])

      Process.sleep(200)

      # Verify different transformations
      transform_signals = MultiTestClient.get_signals(transform_client)
      enrich_signals = MultiTestClient.get_signals(enrich_client)

      assert length(transform_signals) == 1
      assert length(enrich_signals) == 1

      transform_signal = hd(transform_signals)
      enrich_signal = hd(enrich_signals)

      # Transform bus should have modified the type
      assert transform_signal.type == "xformed.test.signal"
      assert transform_signal.data == %{original: "data"}

      # Enrich bus should have modified the data
      assert enrich_signal.type == "test.signal"

      assert enrich_signal.data == %{
               original: "data",
               middleware: "enriched",
               timestamp: "added"
             }

      # Cleanup
      MultiTestClient.stop(transform_client)
      MultiTestClient.stop(enrich_client)

      Logger.info("Independent middleware configurations verified")
    end
  end

  describe "concurrent operations across multiple buses" do
    test "high-load signal processing with multiple buses" do
      Logger.info("Testing high-load concurrent operations")

      # Create 3 buses for load testing
      bus_names =
        Enum.map(1..3, fn i ->
          "load_bus_#{i}_#{:erlang.unique_integer([:positive])}"
        end)

      bus_pids =
        Enum.map(bus_names, fn name ->
          {:ok, pid} =
            start_supervised(
              {Bus,
               name: name,
               middleware: [
                 {MetricsMiddleware, test_pid: self()}
               ]}
            )

          pid
        end)

      # Create multiple clients per bus
      clients_per_bus = 5
      total_clients = length(bus_names) * clients_per_bus

      clients =
        for {bus_pid, bus_index} <- Enum.with_index(bus_pids),
            client_index <- 1..clients_per_bus do
          {:ok, client} = MultiTestClient.start_link(id: "client_#{bus_index}_#{client_index}")

          {:ok, _sub_id} =
            Bus.subscribe(bus_pid, "load.**",
              dispatch: {:pid, target: client, delivery_mode: :async}
            )

          {client, bus_pid}
        end

      Logger.info("Created #{total_clients} clients across #{length(bus_names)} buses")

      # Generate and publish signals concurrently
      signals_per_bus = 50

      publish_tasks =
        for {bus_pid, bus_index} <- Enum.with_index(bus_pids) do
          Task.async(fn ->
            signals =
              Enum.map(1..signals_per_bus, fn signal_index ->
                {:ok, signal} =
                  Signal.new(%{
                    type: "load.test.#{bus_index}.#{signal_index}",
                    source: "/load_test",
                    data: %{bus: bus_index, signal: signal_index, timestamp: DateTime.utc_now()}
                  })

                signal
              end)

            # Publish in smaller batches to simulate real-world usage
            signals
            |> Enum.chunk_every(10)
            |> Enum.each(fn batch ->
              {:ok, _} = Bus.publish(bus_pid, batch)
              Process.sleep(10)
            end)

            :ok
          end)
        end

      # Wait for all publish tasks to complete
      Enum.each(publish_tasks, &Task.await(&1, 10_000))

      Logger.info("All signals published, waiting for delivery")

      # Give time for all signals to be delivered
      Process.sleep(2000)

      # Verify signal delivery
      total_signals_received =
        clients
        |> Enum.map(fn {client, _bus_pid} ->
          signals = MultiTestClient.get_signals(client)
          length(signals)
        end)
        |> Enum.sum()

      expected_total_signals = length(bus_names) * signals_per_bus * clients_per_bus

      assert total_signals_received == expected_total_signals,
             "Expected #{expected_total_signals} total signals, got #{total_signals_received}"

      Logger.info("High-load test completed: #{total_signals_received} signals delivered")

      # Cleanup clients
      Enum.each(clients, fn {client, _bus_pid} ->
        MultiTestClient.stop(client)
      end)
    end
  end
end
