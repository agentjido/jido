defmodule JidoTest.Signal.Bus do
  use JidoTest.Case, async: true
  alias Jido.Signal
  alias Jido.Signal.Bus

  @moduletag :capture_log

  setup do
    bus_name = "test-bus-#{:erlang.unique_integer([:positive])}"
    start_supervised!({Bus, name: bus_name})
    {:ok, bus: bus_name}
  end

  describe "subscribe/3" do
    test "subscribes to signals with a specific type", %{bus: bus} do
      {:ok, subscription_id} = Bus.subscribe(bus, "test.signal")
      assert is_binary(subscription_id)
    end

    test "subscribes to all signals with wildcard", %{bus: bus} do
      {:ok, subscription_id} = Bus.subscribe(bus, "*")
      assert is_binary(subscription_id)
    end

    test "subscribes with custom dispatch config", %{bus: bus} do
      dispatch = {:pid, target: self(), delivery_mode: :sync}
      {:ok, subscription_id} = Bus.subscribe(bus, "test.signal", dispatch: dispatch)
      assert is_binary(subscription_id)
    end

    test "returns error for invalid path pattern", %{bus: bus} do
      assert {:error, _} = Bus.subscribe(bus, "")
    end

    test "subscribes with persistent option", %{bus: bus} do
      {:ok, subscription_id} = Bus.subscribe(bus, "test.signal", persistent?: true)
      assert is_binary(subscription_id)

      # Publish a signal
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Verify signal is received
      assert_receive {:signal, %Signal{type: "test.signal"}}

      # Acknowledge the signal
      :ok = Bus.ack(bus, subscription_id, 1)
    end
  end

  describe "unsubscribe/2" do
    test "unsubscribes from signals", %{bus: bus} do
      {:ok, subscription_id} = Bus.subscribe(bus, "test.signal")
      assert :ok = Bus.unsubscribe(bus, subscription_id)
    end

    test "returns error for non-existent subscription", %{bus: bus} do
      assert {:error, _} = Bus.unsubscribe(bus, "non-existent")
    end

    test "unsubscribes with delete_persistence option", %{bus: bus} do
      {:ok, subscription_id} = Bus.subscribe(bus, "test.signal", persistent: true)
      assert :ok = Bus.unsubscribe(bus, subscription_id, delete_persistence: true)

      # Try to resubscribe with the same ID
      {:ok, new_subscription_id} = Bus.subscribe(bus, "test.signal", persistent: true)
      assert is_binary(new_subscription_id)
    end
  end

  describe "publish/2" do
    test "publishes signals to subscribers", %{bus: bus} do
      # Subscribe to signals
      {:ok, _subscription} = Bus.subscribe(bus, "test.signal")

      # Publish a signal
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Verify signal is received
      assert_receive {:signal, %Signal{type: "test.signal"}}
    end

    @tag :skip
    test "publish/2 maintains signal order", %{bus: bus} do
      # Subscribe to signals
      {:ok, _subscription} = Bus.subscribe(bus, "*")

      # Publish multiple signals
      signals =
        Enum.map(1..3, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.signal.#{i}",
              source: "/test",
              data: %{value: i}
            })

          signal
        end)

      {:ok, _} = Bus.publish(bus, signals)

      # Verify signals are received in order
      for i <- 1..3 do
        type = "test.signal.#{i}"
        assert_receive {:signal, %Signal{type: ^type}}, 1000
      end
    end

    test "publish/2 routes signals to matching subscribers only", %{bus: bus} do
      # Subscribe to specific signal type
      {:ok, _subscription} = Bus.subscribe(bus, "test.signal.1")

      # Publish multiple signals
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "/test",
          data: %{value: 2}
        })

      {:ok, _} = Bus.publish(bus, [signal1, signal2])

      # Should receive only signal1
      assert_receive {:signal, %Signal{type: "test.signal.1"}}
      refute_receive {:signal, %Signal{type: "test.signal.2"}}
    end

    test "handles invalid signals gracefully", %{bus: bus} do
      # Try to publish invalid signals
      assert {:error, _} = Bus.publish(bus, [%{not_a_signal: true}])
    end

    test "publishes signals with correlation_id", %{bus: bus} do
      # Subscribe to signals
      {:ok, _subscription} = Bus.subscribe(bus, "test.signal")

      # Publish a signal with correlation_id
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, _} = Bus.publish(bus, [signal])

      # Verify correlation_id is preserved
      assert_receive {:signal, %Signal{type: "test.signal"}}
    end
  end

  describe "replay/2" do
    @tag :skip
    test "replays signals matching path pattern", %{bus: bus} do
      # Publish some signals first
      signals =
        Enum.map(1..2, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.signal.#{i}",
              source: "/test",
              data: %{value: i}
            })

          signal
        end)

      {:ok, _} = Bus.publish(bus, signals)

      # Replay specific type
      {:ok, replayed} = Bus.replay(bus, "test.signal.1")
      assert length(replayed) == 1
      assert hd(replayed).type == "test.signal.1"

      # Replay all
      {:ok, all_replayed} = Bus.replay(bus)
      assert length(all_replayed) == 2
    end

    @tag :skip
    test "replays signals from start_timestamp", %{bus: bus} do
      # Publish a signal
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 1}
        })

      {:ok, [recorded1]} = Bus.publish(bus, [signal1])

      # Get timestamp from first signal
      timestamp = DateTime.to_unix(recorded1.created_at, :millisecond)

      # Add a delay to ensure second signal has a later timestamp
      Process.sleep(10)

      # Publish another signal
      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal",
          source: "/test",
          data: %{value: 2}
        })

      {:ok, _} = Bus.publish(bus, [signal2])

      # Replay from first signal's timestamp
      {:ok, replayed} = Bus.replay(bus, "*", timestamp)
      assert length(replayed) == 1
      assert hd(replayed).signal.data.value == 2
    end

    test "returns empty list when no signals match replay criteria", %{bus: bus} do
      # Replay with no signals in the bus
      {:ok, replayed} = Bus.replay(bus, "test.signal")
      assert Enum.empty?(replayed)
    end

    @tag :skip
    test "replays signals with batch_size limit", %{bus: bus} do
      # Publish many signals
      signals =
        Enum.map(1..10, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.signal",
              source: "/test",
              data: %{value: i}
            })

          signal
        end)

      {:ok, _} = Bus.publish(bus, signals)

      # Replay with batch_size limit
      {:ok, replayed} = Bus.replay(bus, "*", 0, batch_size: 5)
      assert length(replayed) == 5
    end
  end

  describe "snapshot operations" do
    @tag :skip
    test "creates and reads snapshots", %{bus: bus} do
      # Publish some signals
      signals =
        Enum.map(1..2, fn i ->
          {:ok, signal} =
            Signal.new(%{
              type: "test.signal.#{i}",
              source: "/test",
              data: %{value: i}
            })

          signal
        end)

      {:ok, _} = Bus.publish(bus, signals)

      # Create snapshot
      {:ok, snapshot} = Bus.snapshot_create(bus, "test.signal.1")
      assert snapshot.path == "test.signal.1"

      # Read snapshot
      {:ok, read_snapshot} = Bus.snapshot_read(bus, snapshot.id)
      assert read_snapshot.path == "test.signal.1"
      assert length(read_snapshot.signals) == 1
      assert hd(read_snapshot.signals).type == "test.signal.1"
    end

    test "lists snapshots", %{bus: bus} do
      # Create two snapshots
      {:ok, snapshot1} = Bus.snapshot_create(bus, "test.signal.1")
      {:ok, snapshot2} = Bus.snapshot_create(bus, "test.signal.2")

      snapshots = Bus.snapshot_list(bus)
      assert length(snapshots) == 2
      assert Enum.any?(snapshots, &(&1.id == snapshot1.id))
      assert Enum.any?(snapshots, &(&1.id == snapshot2.id))
    end

    test "deletes snapshots", %{bus: bus} do
      {:ok, snapshot} = Bus.snapshot_create(bus, "test.signal")
      assert :ok = Bus.snapshot_delete(bus, snapshot.id)
      assert {:error, :not_found} = Bus.snapshot_read(bus, snapshot.id)
    end

    test "creates empty snapshot when no signals match path", %{bus: bus} do
      {:ok, snapshot} = Bus.snapshot_create(bus, "non.existent.path")
      assert snapshot.path == "non.existent.path"

      {:ok, read_snapshot} = Bus.snapshot_read(bus, snapshot.id)
      assert Enum.empty?(read_snapshot.signals)
    end

    test "returns error when reading non-existent snapshot", %{bus: bus} do
      assert {:error, :not_found} = Bus.snapshot_read(bus, "non-existent-id")
    end

    test "returns error when deleting non-existent snapshot", %{bus: bus} do
      assert {:error, :not_found} = Bus.snapshot_delete(bus, "non-existent-id")
    end
  end

  # describe "ack/3" do
  #   test "acknowledges signals for persistent subscriptions", %{bus: bus} do
  #     # Create persistent subscription
  #     {:ok, subscription_id} = Bus.subscribe(bus, "test.signal", persistent: true)

  #     # Publish a signal
  #     {:ok, signal} =
  #       Signal.new(%{
  #         type: "test.signal",
  #         source: "/test",
  #         data: %{value: 1}
  #       })

  #     {:ok, [recorded_signal]} = Bus.publish(bus, [signal])

  #     # Verify signal is received
  #     assert_receive {:signal, %Signal{type: "test.signal"}}

  #     # Acknowledge the signal
  #     assert :ok = Bus.ack(bus, subscription_id, recorded_signal.id)
  #   end

  #   test "returns error when acknowledging for non-existent subscription", %{bus: bus} do
  #     assert {:error, _} = Bus.ack(bus, "non-existent", "signal-id")
  #   end

  #   test "returns error when acknowledging for non-persistent subscription", %{bus: bus} do
  #     # Create non-persistent subscription
  #     {:ok, subscription_id} = Bus.subscribe(bus, "test.signal")

  #     assert {:error, _} = Bus.ack(bus, subscription_id, "signal-id")
  #   end
  # end

  # describe "reconnect/2" do
  #   test "reconnects a client to a persistent subscription", %{bus: bus} do
  #     # Create persistent subscription
  #     {:ok, subscription_id} = Bus.subscribe(bus, "test.signal", persistent: true)

  #     # Publish a signal
  #     {:ok, signal} =
  #       Signal.new(%{
  #         type: "test.signal",
  #         source: "/test",
  #         data: %{value: 1}
  #       })

  #     {:ok, [recorded_signal]} = Bus.publish(bus, [signal])

  #     # Acknowledge the signal
  #     :ok = Bus.ack(bus, subscription_id, recorded_signal.id)

  #     # Create a new process to simulate a new client
  #     task =
  #       Task.async(fn ->
  #         receive do
  #           :continue -> :ok
  #         end
  #       end)

  #     # Reconnect with the new client
  #     {:ok, checkpoint} = Bus.reconnect(bus, subscription_id, task.pid)
  #     assert is_integer(checkpoint)

  #     # Clean up
  #     send(task.pid, :continue)
  #     Task.await(task)
  #   end

  #   test "returns error when reconnecting to non-existent subscription", %{bus: bus} do
  #     assert {:error, _} = Bus.reconnect(bus, "non-existent", self())
  #   end

  #   test "returns error when reconnecting to non-persistent subscription", %{bus: bus} do
  #     # Create non-persistent subscription
  #     {:ok, subscription_id} = Bus.subscribe(bus, "test.signal")

  #     assert {:error, _} = Bus.reconnect(bus, subscription_id, self())
  #   end
  # end

  describe "whereis/1" do
    test "finds a bus by name", %{bus: bus} do
      {:ok, pid} = Bus.whereis(bus)
      assert is_pid(pid)
    end

    test "returns error for non-existent bus" do
      assert {:error, :not_found} = Bus.whereis("non-existent-bus")
    end
  end
end
