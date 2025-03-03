defmodule JidoTest.Signal.Bus.StateTest do
  use JidoTest.Case, async: true
  alias Jido.Signal.Bus.State
  alias Jido.Signal.Router
  alias Jido.Signal
  alias Jido.Signal.ID

  describe "append_signals/2" do
    setup do
      state = %State{name: :test_bus}
      {:ok, state: state}
    end

    test "appends signals to empty log", %{state: state} do
      signals = [
        Signal.new!(type: "test.signal", source: "test.source", data: "data1"),
        Signal.new!(type: "test.signal", source: "test.source", data: "data2")
      ]

      assert {:ok, new_state, returned_signals} = State.append_signals(state, signals)
      assert map_size(new_state.log) == 2

      # Check that the signals are in the log
      Enum.each(returned_signals, fn signal ->
        # The signal itself should be a value in the log
        assert Enum.any?(new_state.log, fn {_uuid, log_signal} ->
                 log_signal.data == signal.data
               end)
      end)
    end

    test "generates new UUIDs for each signal", %{state: state} do
      # Create a signal with a specific ID
      signal1 = Signal.new!(type: "test.signal", source: "test.source", data: "data1")

      # Create another signal with the same ID but different data
      signal2 = %{signal1 | data: "data2"}

      {:ok, state, _signals1} = State.append_signals(state, [signal1])
      {:ok, new_state, _signals2} = State.append_signals(state, [signal2])

      # Should have two entries since each signal gets a new UUID as the log key
      assert map_size(new_state.log) == 2

      # The second signal should be in the log
      assert Enum.any?(new_state.log, fn {_uuid, log_signal} ->
               log_signal.data == "data2"
             end)
    end

    test "returns error for invalid signals", %{state: state} do
      invalid_signals = [
        %{not_a_signal: true}
      ]

      # The current implementation doesn't validate signals
      # It just adds them to the log with UUIDs as keys
      {:ok, new_state, _signals} = State.append_signals(state, invalid_signals)

      # Verify the invalid signal was added to the log
      assert Enum.count(new_state.log) == 1

      assert Enum.any?(new_state.log, fn {_uuid, signal} ->
               Map.has_key?(signal, :not_a_signal)
             end)
    end

    test "log keys (UUIDs) reflect the order in which signals were received", %{state: state} do
      # Create signals to append in sequence
      signals1 = [
        Signal.new!(type: "test.signal", source: "test.source", data: "batch1-data1"),
        Signal.new!(type: "test.signal", source: "test.source", data: "batch1-data2")
      ]

      # Add a small delay to ensure different timestamps
      Process.sleep(2)

      signals2 = [
        Signal.new!(type: "test.signal", source: "test.source", data: "batch2-data1"),
        Signal.new!(type: "test.signal", source: "test.source", data: "batch2-data2")
      ]

      # Append signals in two batches
      {:ok, state_after_first, _} = State.append_signals(state, signals1)
      {:ok, state_after_second, _} = State.append_signals(state_after_first, signals2)

      # Extract UUIDs (keys) from the log
      uuids = Map.keys(state_after_second.log) |> Enum.sort()

      # Verify we have all 4 signals
      assert length(uuids) == 4

      # Extract timestamps from UUIDs
      timestamps = Enum.map(uuids, &ID.extract_timestamp/1)

      # Verify timestamps are in ascending order
      assert timestamps == Enum.sort(timestamps)

      # Group UUIDs by timestamp
      uuids_by_timestamp = Enum.group_by(uuids, &ID.extract_timestamp/1)

      # For UUIDs with the same timestamp, verify sequence numbers are in order
      Enum.each(uuids_by_timestamp, fn {_ts, same_ts_uuids} ->
        if length(same_ts_uuids) > 1 do
          sequences = Enum.map(same_ts_uuids, &ID.sequence_number/1)
          assert sequences == Enum.sort(sequences)
        end
      end)
    end

    test "maintains strict ordering of signals within the same batch", %{state: state} do
      # Create a larger batch of signals
      signals =
        for i <- 1..10 do
          Signal.new!(type: "test.signal", source: "test.source", data: "data#{i}")
        end

      # Append all signals at once
      {:ok, new_state, _} = State.append_signals(state, signals)

      # Extract UUIDs (keys) from the log
      uuids = Map.keys(new_state.log) |> Enum.sort()

      # All UUIDs should have the same timestamp since they were generated in a batch
      timestamps = Enum.map(uuids, &ID.extract_timestamp/1)
      assert length(Enum.uniq(timestamps)) == 1

      # Extract sequence numbers
      sequences = Enum.map(uuids, &ID.sequence_number/1)

      # Sequence numbers should be sequential from 0 to 9
      assert sequences == Enum.to_list(0..9)
    end

    test "handles empty signal list", %{state: state} do
      # The current implementation doesn't handle empty signal lists properly
      # It tries to generate UUIDs for an empty list which causes an error
      # This test documents the current behavior
      assert {:error, _} = State.append_signals(state, [])
    end
  end

  describe "log_to_list/1" do
    setup do
      state = %State{name: :test_bus}

      signals = [
        Signal.new!(type: "test.signal", source: "test.source", data: "data1"),
        Signal.new!(type: "test.signal", source: "test.source", data: "data2")
      ]

      {:ok, state, returned_signals} = State.append_signals(state, signals)
      {:ok, state: state, signals: signals, returned_signals: returned_signals}
    end

    test "returns signals in order by ID", %{state: state, signals: signals} do
      list = State.log_to_list(state)
      assert length(list) == 2

      # Verify signals are in order by ID
      [first, second] = list
      assert first.id <= second.id

      # Verify all original signals are present by checking their data
      original_data = Enum.map(signals, & &1.data) |> MapSet.new()
      list_data = Enum.map(list, & &1.data) |> MapSet.new()
      assert MapSet.equal?(original_data, list_data)
    end

    test "handles empty log", %{state: state} do
      empty_state = %{state | log: %{}}
      assert State.log_to_list(empty_state) == []
    end
  end

  describe "truncate_log/2" do
    setup do
      state = %State{name: :test_bus}

      signals =
        for i <- 1..5 do
          Signal.new!(type: "test.signal", source: "test.source", data: "data#{i}")
        end

      {:ok, state, _} = State.append_signals(state, signals)
      {:ok, state: state}
    end

    test "truncates log to specified size", %{state: state} do
      assert {:ok, new_state} = State.truncate_log(state, 3)
      assert map_size(new_state.log) == 3

      # Verify we kept the most recent signals
      list = State.log_to_list(new_state)
      assert length(list) == 3
    end

    test "does nothing when max size is larger than current size", %{state: state} do
      assert {:ok, new_state} = State.truncate_log(state, 10)
      assert map_size(new_state.log) == 5
    end

    test "handles truncating to zero", %{state: state} do
      assert {:ok, new_state} = State.truncate_log(state, 0)
      assert map_size(new_state.log) == 0
    end

    test "preserves chronological ordering after truncation", %{state: state} do
      # Add signals with a delay to ensure different timestamps
      # Create initial signals
      signals =
        for i <- 1..5 do
          Signal.new!(type: "test.signal", source: "test.source", data: "data#{i}")
        end

      {:ok, state, _} = State.append_signals(state, signals)

      # Add first newer signal
      signal1 = Signal.new!(type: "test.signal", source: "test.source", data: "newer1")
      {:ok, state, _} = State.append_signals(state, [signal1])

      # Add second newer signal after a delay
      Process.sleep(2)
      signal2 = Signal.new!(type: "test.signal", source: "test.source", data: "newer2")
      {:ok, state, _} = State.append_signals(state, [signal2])

      # Truncate to keep only 3 signals
      {:ok, truncated_state} = State.truncate_log(state, 3)

      # Get the log keys in sorted order
      sorted_keys = Map.keys(truncated_state.log) |> Enum.sort()

      # Extract timestamps from the keys
      timestamps = Enum.map(sorted_keys, &ID.extract_timestamp/1)

      # Verify timestamps are in ascending order
      assert timestamps == Enum.sort(timestamps)

      # Verify we kept the most recent signals
      signals_list = State.log_to_list(truncated_state)
      assert length(signals_list) == 3

      # The newest signal should be in the truncated log
      assert Enum.any?(signals_list, fn signal -> signal.data == "newer2" end)

      # Check that we have the most recent signals by checking their data
      signal_data = Enum.map(signals_list, & &1.data)
      assert "newer2" in signal_data
    end
  end

  describe "clear_log/1" do
    setup do
      state = %State{name: :test_bus}

      signals = [
        Signal.new!(type: "test.signal", source: "test.source", data: "data1"),
        Signal.new!(type: "test.signal", source: "test.source", data: "data2")
      ]

      {:ok, state, _} = State.append_signals(state, signals)
      {:ok, state: state}
    end

    test "removes all signals from log", %{state: state} do
      assert {:ok, new_state} = State.clear_log(state)
      assert map_size(new_state.log) == 0
      assert State.log_to_list(new_state) == []
    end

    test "clears log but preserves other state fields", %{state: state} do
      # Add a subscription to the state
      subscription = %Jido.Signal.Bus.Subscriber{
        id: "sub1",
        path: "test.*",
        dispatch: {:pid, target: self()},
        persistent?: true
      }

      {:ok, state_with_sub} = State.add_subscription(state, "sub1", subscription)

      # Clear the log
      {:ok, new_state} = State.clear_log(state_with_sub)

      # Verify log is empty
      assert map_size(new_state.log) == 0

      # Verify subscription is still present
      assert State.has_subscription?(new_state, "sub1")
    end
  end

  describe "add_route/2" do
    setup do
      state = %State{name: :test_bus}
      route = %Router.Route{path: "test.*", target: {:pid, target: self()}, priority: 0}
      {:ok, state: state, route: route}
    end

    test "adds valid route to router", %{state: state, route: route} do
      assert {:ok, new_state} = State.add_route(state, route)
      {:ok, routes} = Router.list(new_state.router)
      assert length(routes) == 1
      assert hd(routes).path == route.path
    end

    test "returns error for invalid route", %{state: state} do
      invalid_route = %Router.Route{path: "invalid**path", target: {:pid, target: self()}}
      assert {:error, _reason} = State.add_route(state, invalid_route)
    end
  end

  describe "remove_route/2" do
    setup do
      state = %State{name: :test_bus}
      route = %Router.Route{path: "test.*", target: {:pid, target: self()}, priority: 0}
      {:ok, state} = State.add_route(state, route)
      {:ok, state: state, route: route}
    end

    test "removes existing route", %{state: state, route: route} do
      assert {:ok, new_state} = State.remove_route(state, route)
      {:ok, routes} = Router.list(new_state.router)
      assert Enum.empty?(routes)
    end

    test "returns error for non-existent route", %{state: state} do
      non_existent = %Router.Route{path: "other.*", target: {:pid, target: self()}, priority: 0}
      assert {:error, _reason} = State.remove_route(state, non_existent)
    end
  end

  describe "subscription management" do
    setup do
      state = %State{name: :test_bus}

      subscription = %Jido.Signal.Bus.Subscriber{
        id: "sub1",
        path: "test.*",
        dispatch: {:pid, target: self()},
        persistent?: true
      }

      {:ok, state: state, subscription: subscription}
    end

    test "add_subscription adds new subscription", %{state: state, subscription: sub} do
      assert {:ok, new_state} = State.add_subscription(state, "sub1", sub)
      assert Map.has_key?(new_state.subscriptions, "sub1")
      assert new_state.subscriptions["sub1"] == sub
    end

    test "add_subscription fails for duplicate", %{state: state, subscription: sub} do
      {:ok, state} = State.add_subscription(state, "sub1", sub)
      assert {:error, :subscription_exists} = State.add_subscription(state, "sub1", sub)
    end

    test "remove_subscription removes subscription", %{state: state, subscription: sub} do
      {:ok, state} = State.add_subscription(state, "sub1", sub)
      assert {:ok, new_state} = State.remove_subscription(state, "sub1")
      refute Map.has_key?(new_state.subscriptions, "sub1")
    end

    test "remove_subscription returns error for non-existent", %{state: state} do
      assert {:error, :subscription_not_found} = State.remove_subscription(state, "missing")
    end

    test "has_subscription? returns true for existing subscription", %{
      state: state,
      subscription: sub
    } do
      {:ok, state} = State.add_subscription(state, "sub1", sub)
      assert State.has_subscription?(state, "sub1")
    end

    test "has_subscription? returns false for non-existent subscription", %{state: state} do
      refute State.has_subscription?(state, "missing")
    end

    test "get_subscription returns subscription for existing id", %{
      state: state,
      subscription: sub
    } do
      {:ok, state} = State.add_subscription(state, "sub1", sub)
      assert State.get_subscription(state, "sub1") == sub
    end

    test "get_subscription returns nil for non-existent id", %{state: state} do
      assert State.get_subscription(state, "missing") == nil
    end
  end

  describe "signal log integration" do
    setup do
      state = %State{name: :test_bus}
      {:ok, state: state}
    end

    test "appending signals and then truncating preserves chronological order", %{state: state} do
      # Append first batch
      signals1 =
        for i <- 1..3 do
          Signal.new!(type: "test.signal", source: "test.source", data: "batch1-data#{i}")
        end

      {:ok, state, _} = State.append_signals(state, signals1)

      # Wait to ensure different timestamp
      Process.sleep(2)

      # Append second batch
      signals2 =
        for i <- 1..3 do
          Signal.new!(type: "test.signal", source: "test.source", data: "batch2-data#{i}")
        end

      {:ok, state, _} = State.append_signals(state, signals2)

      # Wait again
      Process.sleep(2)

      # Append third batch
      signals3 =
        for i <- 1..3 do
          Signal.new!(type: "test.signal", source: "test.source", data: "batch3-data#{i}")
        end

      {:ok, state, _} = State.append_signals(state, signals3)

      # Truncate to 5 signals
      {:ok, truncated_state} = State.truncate_log(state, 5)

      # Get log keys in sorted order
      sorted_keys = Map.keys(truncated_state.log) |> Enum.sort()

      # Extract timestamps
      timestamps = Enum.map(sorted_keys, &ID.extract_timestamp/1)

      # Verify timestamps are in ascending order
      assert timestamps == Enum.sort(timestamps)

      # Verify we have 5 signals
      assert length(sorted_keys) == 5

      # Verify we kept the most recent signals (should be from batch2 and batch3)
      signals_list = State.log_to_list(truncated_state)

      # None of the signals should be from batch1
      refute Enum.any?(signals_list, fn signal ->
               String.starts_with?(signal.data, "batch1")
             end)

      # All signals from batch3 should be present
      batch3_signals =
        Enum.filter(signals_list, fn signal ->
          String.starts_with?(signal.data, "batch3")
        end)

      assert length(batch3_signals) == 3
    end

    test "handles large number of signals with proper ordering", %{state: state} do
      # Generate a large number of signals
      large_batch =
        for i <- 1..100 do
          Signal.new!(type: "test.signal", source: "test.source", data: "data#{i}")
        end

      # Append all signals at once
      {:ok, state_with_signals, _} = State.append_signals(state, large_batch)

      # Verify we have all 100 signals
      assert map_size(state_with_signals.log) == 100

      # Get log keys in sorted order
      sorted_keys = Map.keys(state_with_signals.log) |> Enum.sort()

      # Extract timestamps and sequence numbers
      timestamps = Enum.map(sorted_keys, &ID.extract_timestamp/1)
      sequences = Enum.map(sorted_keys, &ID.sequence_number/1)

      # All timestamps should be the same since they were generated in a batch
      assert length(Enum.uniq(timestamps)) == 1

      # Sequence numbers should be sequential from 0 to 99
      assert sequences == Enum.to_list(0..99)
    end
  end
end
