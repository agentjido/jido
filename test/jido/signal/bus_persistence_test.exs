defmodule JidoTest.Signal.Bus.PersistentSubscriptionTest do
  use JidoTest.Case, async: true
  alias Jido.Signal.Bus.PersistentSubscription
  alias Jido.Signal
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.ID
  require Logger

  # Uncomment to see detailed logs during test execution
  # @moduletag :capture_log

  describe "persistent subscription" do
    setup do
      bus_name = :"bus_#{System.unique_integer()}"
      bus_pid = start_supervised!({Bus, name: bus_name})
      test_pid = self()

      {:ok, bus_pid: bus_pid, test_pid: test_pid}
    end

    test "starts a persistent subscription", %{bus_pid: bus_pid, test_pid: test_pid} do
      opts = [
        bus_pid: bus_pid,
        path: "test/path",
        client_pid: test_pid,
        bus_subscription: %{dispatch: []}
      ]

      {:ok, pid} = PersistentSubscription.start_link(opts)
      assert Process.alive?(pid)
    end

    test "accepts signal and forwards to subscriber", %{bus_pid: bus_pid, test_pid: test_pid} do
      # First verify that direct dispatch works correctly
      direct_dispatch_config = [{:pid, [target: test_pid]}]
      test_signal = Signal.new!(%{type: "direct-test", source: "/test", data: %{test: "direct"}})

      # This should send a message directly to our test process
      :ok = Jido.Signal.Dispatch.dispatch(test_signal, direct_dispatch_config)

      # Verify we received the direct test signal
      assert_receive {:signal, direct_signal}, 500
      assert direct_signal.type == "direct-test"
      assert direct_signal.data == %{test: "direct"}

      # Now set up the persistent subscription with the correct dispatch format
      dispatch_config = [{:pid, [target: test_pid]}]

      opts = [
        bus_pid: bus_pid,
        path: "test/path",
        client_pid: test_pid,
        bus_subscription: %Subscriber{
          id: ID.generate!(),
          path: "test/path",
          dispatch: dispatch_config
        }
      ]

      # Start the persistent subscription
      {:ok, persistent_pid} = PersistentSubscription.start_link(opts)

      # Create a test signal to send through the subscription
      signal =
        Signal.new!(%{
          type: "test-type",
          source: "/test",
          data: %{test: "data"}
        })

      # Generate a UUID7 for the signal log ID
      signal_log_id = ID.generate!()

      # Send signal to subscription process
      send(persistent_pid, {:signal, {signal_log_id, signal}})

      # The subscription should dispatch the signal to our test process
      # We should receive it wrapped in a {:signal, signal} tuple
      assert_eventually(
        fn ->
          receive do
            {:signal, received_signal} ->
              received_signal.type == signal.type and received_signal.data == signal.data
          after
            0 -> false
          end
        end,
        timeout: 1000
      )

      # Verify the signal is tracked in the subscription's in-flight map
      state = :sys.get_state(persistent_pid)
      assert map_size(state.in_flight_signals) == 1
      assert Map.has_key?(state.in_flight_signals, signal_log_id)
    end

    test "handles signal acknowledgment", %{bus_pid: bus_pid, test_pid: test_pid} do
      # Set up the persistent subscription with max_in_flight=1 to test queuing
      dispatch_config = [{:pid, [target: test_pid]}]

      opts = [
        bus_pid: bus_pid,
        path: "test/path",
        client_pid: test_pid,
        # Only allow 1 in-flight signal at a time
        max_in_flight: 1,
        bus_subscription: %Subscriber{
          id: ID.generate!(),
          path: "test/path",
          dispatch: dispatch_config
        }
      ]

      {:ok, pid} = PersistentSubscription.start_link(opts)

      # Create two test signals
      signal1 =
        Signal.new!(%{
          type: "test-type-1",
          source: "/test",
          data: %{test: "data1"}
        })

      signal2 =
        Signal.new!(%{
          type: "test-type-2",
          source: "/test",
          data: %{test: "data2"}
        })

      # Generate UUID7s for signal log IDs
      signal_log_id1 = ID.generate!()
      signal_log_id2 = ID.generate!()

      # Send first signal
      send(pid, {:signal, {signal_log_id1, signal1}})

      # We should receive the first signal
      assert_receive {:signal, received_signal1}, 500
      assert received_signal1.type == "test-type-1"
      assert received_signal1.data == %{test: "data1"}

      # Verify first signal is in-flight
      state_after_first = :sys.get_state(pid)
      assert map_size(state_after_first.in_flight_signals) == 1
      assert Map.has_key?(state_after_first.in_flight_signals, signal_log_id1)
      assert map_size(state_after_first.pending_signals) == 0

      # Send second signal
      send(pid, {:signal, {signal_log_id2, signal2}})

      # We should NOT receive the second signal yet (max_in_flight=1)
      refute_receive {:signal, _}, 100

      # Verify second signal is pending, not in-flight
      state_after_second = :sys.get_state(pid)
      assert map_size(state_after_second.in_flight_signals) == 1
      assert map_size(state_after_second.pending_signals) == 1
      assert Map.has_key?(state_after_second.pending_signals, signal_log_id2)

      # Acknowledge first signal
      :ok = GenServer.call(pid, {:ack, signal_log_id1})

      # Verify checkpoint was updated
      state_after_ack = :sys.get_state(pid)

      # With UUID7, the checkpoint will be the timestamp from the UUID
      checkpoint_timestamp = ID.extract_timestamp(signal_log_id1)
      assert state_after_ack.checkpoint == checkpoint_timestamp

      # First signal should be removed from in-flight
      assert map_size(state_after_ack.in_flight_signals) == 1
      refute Map.has_key?(state_after_ack.in_flight_signals, signal_log_id1)

      # Second signal should now be in-flight
      assert Map.has_key?(state_after_ack.in_flight_signals, signal_log_id2)

      # Pending signals should be empty
      assert map_size(state_after_ack.pending_signals) == 0

      # We should now receive the second signal
      assert_receive {:signal, received_signal2}, 500
      assert received_signal2.type == "test-type-2"
      assert received_signal2.data == %{test: "data2"}
    end

    test "handles batch acknowledgment", %{bus_pid: bus_pid, test_pid: test_pid} do
      # Set up the persistent subscription
      dispatch_config = [{:pid, [target: test_pid]}]

      opts = [
        bus_pid: bus_pid,
        path: "test/path",
        client_pid: test_pid,
        # Allow multiple in-flight signals
        max_in_flight: 10,
        bus_subscription: %Subscriber{
          id: ID.generate!(),
          path: "test/path",
          dispatch: dispatch_config
        }
      ]

      {:ok, pid} = PersistentSubscription.start_link(opts)

      # Create and send multiple signals with UUID7 IDs
      # Generate 5 signals with UUID7 IDs
      signals_with_ids =
        for i <- 1..5 do
          signal =
            Signal.new!(%{
              type: "test-type-#{i}",
              source: "/test",
              data: %{test: "data#{i}"}
            })

          # Generate a UUID7 for the signal log ID
          signal_log_id = ID.generate!()

          # Send signal with UUID7 ID
          send(pid, {:signal, {signal_log_id, signal}})

          {signal_log_id, signal}
        end

      # Extract just the signal_log_ids for later use
      signal_log_ids = Enum.map(signals_with_ids, fn {id, _} -> id end)

      # We should receive all signals
      for i <- 1..5 do
        assert_receive {:signal, received_signal}, 500
        assert received_signal.type == "test-type-#{i}"
        assert received_signal.data == %{test: "data#{i}"}
      end

      # Verify all signals are in-flight
      state_before_ack = :sys.get_state(pid)
      assert map_size(state_before_ack.in_flight_signals) == 5

      # Select 3 signal IDs to acknowledge (first, third, and fifth)
      ids_to_ack = [
        Enum.at(signal_log_ids, 0),
        Enum.at(signal_log_ids, 2),
        Enum.at(signal_log_ids, 4)
      ]

      # Acknowledge signals in a batch
      :ok = GenServer.call(pid, {:ack, ids_to_ack})

      # Verify checkpoint was updated to highest acknowledged ID timestamp
      state_after_ack = :sys.get_state(pid)

      # Find the highest timestamp from the acknowledged IDs
      highest_timestamp =
        ids_to_ack
        |> Enum.map(&ID.extract_timestamp/1)
        |> Enum.max()

      assert state_after_ack.checkpoint == highest_timestamp

      # The acknowledged signals should be removed from in-flight
      assert map_size(state_after_ack.in_flight_signals) == 2

      # First, third, and fifth signals should be removed
      refute Map.has_key?(state_after_ack.in_flight_signals, Enum.at(signal_log_ids, 0))
      assert Map.has_key?(state_after_ack.in_flight_signals, Enum.at(signal_log_ids, 1))
      refute Map.has_key?(state_after_ack.in_flight_signals, Enum.at(signal_log_ids, 2))
      assert Map.has_key?(state_after_ack.in_flight_signals, Enum.at(signal_log_ids, 3))
      refute Map.has_key?(state_after_ack.in_flight_signals, Enum.at(signal_log_ids, 4))
    end
  end
end
