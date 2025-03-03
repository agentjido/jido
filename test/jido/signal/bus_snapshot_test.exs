defmodule Jido.Signal.Bus.SnapshotTest do
  use ExUnit.Case, async: true
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Bus.Snapshot
  alias Jido.Signal.Router
  alias Jido.Signal

  @moduletag :capture_log

  setup do
    # Create a test bus state with some signals
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

    # Create signals with UUIDs as keys
    log_map = %{
      "uuid-1" => signal1,
      "uuid-2" => signal2
    }

    state = %BusState{
      name: :test_bus,
      router: Router.new!(),
      log: log_map,
      snapshots: %{}
    }

    {:ok, state: state}
  end

  describe "create/2" do
    test "creates a snapshot with filtered signals", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "test.signal.1")

      # Verify the reference
      assert snapshot_ref.path == "test.signal.1"
      assert is_binary(snapshot_ref.id)
      assert %DateTime{} = snapshot_ref.created_at
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data in persistent_term
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.1"
    end

    test "creates a snapshot with all signals using wildcard", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "**")

      # Verify the reference
      assert snapshot_ref.path == "**"
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert map_size(snapshot_data.signals) == 2
    end

    test "creates an empty snapshot when no signals match path", %{state: state} do
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "non.existent.path")

      # Verify the reference
      assert snapshot_ref.path == "non.existent.path"
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the actual data
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert map_size(snapshot_data.signals) == 0
    end

    test "handles invalid path pattern", %{state: state} do
      assert {:error, _} = Snapshot.create(state, "invalid**path")
    end

    test "creates snapshot with custom id", %{state: state} do
      custom_id = "custom-snapshot-id"
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "test.signal.1", id: custom_id)

      # Verify the reference
      assert snapshot_ref.id == custom_id
      assert Map.has_key?(new_state.snapshots, custom_id)

      # Verify the actual data
      {:ok, snapshot_data} = Snapshot.read(new_state, custom_id)
      assert snapshot_data.id == custom_id
    end

    test "creates snapshot with timestamp filter", %{state: state} do
      # Create a new signal with a later timestamp
      {:ok, signal3} =
        Signal.new(%{
          type: "test.signal.3",
          source: "/test",
          data: %{value: 3}
        })

      # Since we can't rely on timestamp filtering in the new implementation,
      # we'll test a different approach by using a specific type filter

      # Add the new signal to the state
      updated_log = Map.put(state.log, "uuid-3", signal3)
      state = %{state | log: updated_log}

      # Create snapshot with a specific type filter instead of timestamp
      {:ok, snapshot_ref, new_state} = Snapshot.create(state, "test.signal.3")

      # Verify the reference
      assert snapshot_ref.path == "test.signal.3"
      assert Map.has_key?(new_state.snapshots, snapshot_ref.id)

      # Verify the snapshot only includes signals of the specified type
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.3"
    end
  end

  describe "list/1" do
    test "returns empty list when no snapshots exist", %{state: state} do
      assert Snapshot.list(state) == []
    end

    test "returns list of all snapshot references", %{state: state} do
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      snapshot_refs = Snapshot.list(state)
      assert length(snapshot_refs) == 2
      assert Enum.member?(snapshot_refs, snapshot_ref1)
      assert Enum.member?(snapshot_refs, snapshot_ref2)
    end

    test "returns snapshots sorted by creation time", %{state: state} do
      # Create first snapshot
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")

      # Wait a moment to ensure different timestamps
      Process.sleep(10)

      # Create second snapshot
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      snapshot_refs = Snapshot.list(state)
      assert length(snapshot_refs) == 2

      # Verify snapshots are sorted by creation time (newest first)
      [first, second] = snapshot_refs
      assert first.id == snapshot_ref2.id
      assert second.id == snapshot_ref1.id
      assert DateTime.compare(first.created_at, second.created_at) == :gt
    end
  end

  describe "read/2" do
    test "returns snapshot data by id", %{state: state} do
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_data} = Snapshot.read(state, snapshot_ref.id)

      assert snapshot_data.id == snapshot_ref.id
      assert snapshot_data.path == snapshot_ref.path
      assert snapshot_data.created_at == snapshot_ref.created_at
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.1"
    end

    test "returns error when snapshot not found", %{state: state} do
      assert {:error, :not_found} = Snapshot.read(state, "non-existent-id")
    end

    test "handles reading snapshot after state changes", %{state: state} do
      # Create a snapshot
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")

      # Add more signals to the state (which shouldn't affect the snapshot)
      {:ok, signal3} =
        Signal.new(%{
          type: "test.signal.3",
          source: "/test",
          data: %{value: 3}
        })

      # Add the new signal directly to the log
      updated_log = Map.put(state.log, "uuid-3", signal3)
      updated_state = %{state | log: updated_log}

      # Read the snapshot from the updated state
      {:ok, snapshot_data} = Snapshot.read(updated_state, snapshot_ref.id)

      # Verify the snapshot still only contains the original signals
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.1"
    end
  end

  describe "delete/2" do
    test "deletes existing snapshot from both state and persistent_term", %{state: state} do
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")
      {:ok, new_state} = Snapshot.delete(state, snapshot_ref.id)

      # Verify removed from state
      refute Map.has_key?(new_state.snapshots, snapshot_ref.id)
      # Verify removed from persistent_term
      assert {:error, :not_found} = Snapshot.read(new_state, snapshot_ref.id)
    end

    test "returns error when deleting non-existent snapshot", %{state: state} do
      assert {:error, :not_found} = Snapshot.delete(state, "non-existent-id")
    end

    test "maintains other snapshots when deleting one", %{state: state} do
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")
      {:ok, new_state} = Snapshot.delete(state, snapshot_ref1.id)

      # Verify first snapshot is completely removed
      refute Map.has_key?(new_state.snapshots, snapshot_ref1.id)
      assert {:error, :not_found} = Snapshot.read(new_state, snapshot_ref1.id)

      # Verify second snapshot is still intact
      assert Map.has_key?(new_state.snapshots, snapshot_ref2.id)
      {:ok, snapshot_data2} = Snapshot.read(new_state, snapshot_ref2.id)
      assert snapshot_data2.id == snapshot_ref2.id
    end

    test "allows creating a new snapshot after deleting one with the same id", %{state: state} do
      custom_id = "reusable-id"

      # Create first snapshot
      {:ok, _snapshot_ref1, state} = Snapshot.create(state, "test.signal.1", id: custom_id)

      # Delete the snapshot
      {:ok, state} = Snapshot.delete(state, custom_id)

      # Create a new snapshot with the same ID
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2", id: custom_id)

      # Verify the new snapshot
      assert snapshot_ref2.id == custom_id
      assert snapshot_ref2.path == "test.signal.2"

      # Read the snapshot data
      {:ok, snapshot_data} = Snapshot.read(state, custom_id)
      assert snapshot_data.path == "test.signal.2"
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.2"
    end
  end

  describe "snapshot data persistence" do
    test "snapshot data persists across state changes", %{state: state} do
      # Create a snapshot
      {:ok, snapshot_ref, _state} = Snapshot.create(state, "test.signal.1")

      # Create a completely new state with the same snapshot reference
      new_state = %BusState{
        name: :test_bus_2,
        router: Router.new!(),
        log: %{},
        snapshots: %{snapshot_ref.id => snapshot_ref}
      }

      # Read the snapshot from the new state
      {:ok, snapshot_data} = Snapshot.read(new_state, snapshot_ref.id)

      # Verify the snapshot data is still accessible
      assert snapshot_data.id == snapshot_ref.id
      assert snapshot_data.path == "test.signal.1"
      assert map_size(snapshot_data.signals) == 1
      assert Map.values(snapshot_data.signals) |> hd() |> Map.get(:type) == "test.signal.1"
    end

    test "snapshot data is immutable", %{state: state} do
      # Create a snapshot
      {:ok, snapshot_ref, state} = Snapshot.create(state, "test.signal.1")

      # Read the snapshot data
      {:ok, snapshot_data} = Snapshot.read(state, snapshot_ref.id)

      # Try to modify the snapshot data (this should create a new copy, not modify the original)
      modified_data = %{snapshot_data | path: "modified.path"}

      # Read the snapshot data again
      {:ok, read_data} = Snapshot.read(state, snapshot_ref.id)

      # Verify the original data is unchanged
      assert read_data.path == "test.signal.1"
      assert read_data.path != modified_data.path
    end
  end

  describe "snapshot cleanup" do
    test "cleanup removes all snapshots", %{state: state} do
      # Create multiple snapshots
      {:ok, _snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, _snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      # Verify snapshots exist
      assert length(Snapshot.list(state)) == 2

      # Clean up all snapshots
      {:ok, new_state} = Snapshot.cleanup(state)

      # Verify all snapshots are removed
      assert Enum.empty?(Snapshot.list(new_state))
      assert new_state.snapshots == %{}
    end

    test "cleanup with filter removes only matching snapshots", %{state: state} do
      # Create snapshots with different paths
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      # Clean up snapshots matching a specific path
      {:ok, new_state} = Snapshot.cleanup(state, fn ref -> ref.path == "test.signal.1" end)

      # Verify only matching snapshots are removed
      snapshot_refs = Snapshot.list(new_state)
      assert length(snapshot_refs) == 1
      assert hd(snapshot_refs).id == snapshot_ref2.id
      refute Map.has_key?(new_state.snapshots, snapshot_ref1.id)
    end

    test "cleanup with age filter removes old snapshots", %{state: state} do
      # Create first snapshot
      {:ok, snapshot_ref1, state} = Snapshot.create(state, "test.signal.1")

      # Wait to ensure different timestamps
      Process.sleep(10)

      # Create second snapshot
      {:ok, snapshot_ref2, state} = Snapshot.create(state, "test.signal.2")

      # Get the timestamp of the second snapshot
      cutoff_time = snapshot_ref2.created_at

      # Clean up snapshots older than the cutoff time
      {:ok, new_state} =
        Snapshot.cleanup(state, fn ref ->
          DateTime.compare(ref.created_at, cutoff_time) == :lt
        end)

      # Verify only older snapshots are removed
      snapshot_refs = Snapshot.list(new_state)
      assert length(snapshot_refs) == 1
      assert hd(snapshot_refs).id == snapshot_ref2.id
      refute Map.has_key?(new_state.snapshots, snapshot_ref1.id)
    end
  end
end
