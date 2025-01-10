defmodule Jido.Bus.Examples.ExampleBusTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Phoenix.PubSub

  describe "pubsub bus" do
    setup do
      test_name = :"pubsub_#{:erlang.unique_integer()}"
      pubsub_name = :"#{test_name}_pubsub"

      # Start Phoenix.PubSub
      {:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: pubsub_name)

      # Start bus with pubsub adapter
      {:ok, bus} =
        Jido.Bus.start_link(
          name: test_name,
          adapter: :pubsub,
          pubsub_name: pubsub_name
        )

      {:ok, %{bus: bus, pubsub_name: pubsub_name, test_name: test_name}}
    end

    test "can publish and subscribe to signals", %{pubsub_name: pubsub_name, test_name: test_name} do
      # Subscribe directly to PubSub
      :ok = PubSub.subscribe(pubsub_name, "test_stream")

      # Create and publish a signal
      signal = %Signal{
        id: UUID.uuid4(),
        source: "test",
        type: "test.event",
        data: %{value: 123}
      }

      :ok = Jido.Bus.publish(test_name, "test_stream", :any_version, [signal])

      # Verify we receive the signal
      assert_receive {:signal, received_signal}
      assert received_signal.id == signal.id
      assert received_signal.data.value == 123
    end
  end

  describe "in-memory bus" do
    setup do
      test_name = :"memory_#{:erlang.unique_integer()}"

      {:ok, bus} =
        Jido.Bus.start_link(
          name: test_name,
          adapter: :in_memory
        )

      {:ok, %{bus: bus, test_name: test_name}}
    end

    test "supports signal replay", %{test_name: test_name} do
      # Publish some signals
      signals =
        for i <- 1..3 do
          %Signal{
            id: UUID.uuid4(),
            source: "test",
            type: "test.event",
            data: %{value: i}
          }
        end

      :ok = Jido.Bus.publish(test_name, "test_stream", :any_version, signals)

      # Replay and verify
      replayed = Jido.Bus.replay(test_name, "test_stream") |> Enum.to_list()
      assert length(replayed) == 3
      assert Enum.map(replayed, & &1.data.value) == [1, 2, 3]
    end

    test "supports snapshots", %{test_name: test_name} do
      snapshot = %Jido.Bus.Snapshot{
        source_id: "test_source",
        source_version: 1,
        source_type: "TestAggregate",
        data: %{state: "test_state"},
        created_at: DateTime.utc_now()
      }

      :ok = Jido.Bus.record_snapshot(test_name, snapshot)

      {:ok, retrieved} = Jido.Bus.read_snapshot(test_name, "test_source")
      assert retrieved.data.state == "test_state"

      :ok = Jido.Bus.delete_snapshot(test_name, "test_source")
      assert {:error, :snapshot_not_found} = Jido.Bus.read_snapshot(test_name, "test_source")
    end
  end
end
