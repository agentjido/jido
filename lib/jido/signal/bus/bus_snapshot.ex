defmodule Jido.Signal.Bus.Snapshot do
  @moduledoc """
  Manages snapshots of the bus's signal log. A snapshot represents a filtered view
  of signals at a particular point in time, filtered by a path pattern.

  Snapshots are immutable once created and are stored in :persistent_term for efficiency.
  The bus state only maintains lightweight references to the snapshots.

  ## Usage

  ```elixir
  # Create a snapshot of all signals
  {:ok, snapshot_ref, new_state} = Snapshot.create(state, "*")

  # Create a snapshot of specific signal types
  {:ok, snapshot_ref, new_state} = Snapshot.create(state, "user.created")

  # Create a snapshot with a custom ID
  {:ok, snapshot_ref, new_state} = Snapshot.create(state, "user.created", id: "my-custom-id")

  # Create a snapshot with signals after a specific timestamp
  timestamp = DateTime.utc_now() |> DateTime.to_unix(:millisecond)
  {:ok, snapshot_ref, new_state} = Snapshot.create(state, "*", start_timestamp: timestamp)

  # List all snapshots
  snapshots = Snapshot.list(state)

  # Read a snapshot
  {:ok, snapshot_data} = Snapshot.read(state, snapshot_ref.id)

  # Delete a snapshot
  {:ok, new_state} = Snapshot.delete(state, snapshot_ref.id)

  # Clean up all snapshots
  {:ok, new_state} = Snapshot.cleanup(state)

  # Clean up snapshots matching a filter
  {:ok, new_state} = Snapshot.cleanup(state, fn ref -> ref.path == "user.created" end)
  ```
  """
  use TypedStruct
  use ExDbug, enabled: false
  alias Jido.Signal.Bus.State, as: BusState
  alias Jido.Signal.Bus.Stream
  alias Jido.Signal.ID
  require Logger

  typedstruct module: SnapshotRef do
    @moduledoc """
    A lightweight reference to a snapshot stored in :persistent_term.
    Contains only the metadata needed for listing and lookup.

    ## Fields

    * `id` - Unique identifier for the snapshot
    * `path` - The path pattern used to filter signals
    * `created_at` - When the snapshot was created
    """
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end

  typedstruct module: SnapshotData do
    @moduledoc """
    The actual snapshot data stored in :persistent_term.
    Contains the full signal list and metadata.

    ## Fields

    * `id` - Unique identifier for the snapshot
    * `path` - The path pattern used to filter signals
    * `signals` - Map of recorded signals matching the path pattern, keyed by signal ID
    * `created_at` - When the snapshot was created
    """
    field(:id, String.t(), enforce: true)
    field(:path, String.t(), enforce: true)
    field(:signals, %{String.t() => Jido.Signal.Bus.Signal.t()}, enforce: true)
    field(:created_at, DateTime.t(), enforce: true)
  end

  @doc """
  Creates a new snapshot of signals matching the given path pattern.
  Stores the snapshot data in :persistent_term and returns a reference.
  Returns {:ok, snapshot_ref, new_state} on success or {:error, reason} on failure.

  ## Options

  * `:id` - Custom ID for the snapshot (optional)
  * `:start_timestamp` - Only include signals after this timestamp in milliseconds (optional)
  * `:correlation_id` - Only include signals with this correlation ID (optional)
  * `:batch_size` - Maximum number of signals to include (optional, defaults to 1000)

  ## Examples

      iex> Snapshot.create(state, "*")
      {:ok, %SnapshotRef{}, %BusState{}}

      iex> Snapshot.create(state, "user.created", id: "my-snapshot")
      {:ok, %SnapshotRef{id: "my-snapshot"}, %BusState{}}

      iex> Snapshot.create(state, "*", start_timestamp: 1612345678000)
      {:ok, %SnapshotRef{}, %BusState{}}
  """
  @spec create(BusState.t(), String.t(), Keyword.t()) ::
          {:ok, SnapshotRef.t(), BusState.t()} | {:error, term()}
  def create(state, path, opts \\ []) do
    dbug("create", path: path, state: state)

    # Extract options
    custom_id = Keyword.get(opts, :id)
    start_timestamp = Keyword.get(opts, :start_timestamp)
    correlation_id = Keyword.get(opts, :correlation_id)
    batch_size = Keyword.get(opts, :batch_size, 1_000)

    # Prepare filter options
    filter_opts = [batch_size: batch_size]

    filter_opts =
      if correlation_id,
        do: Keyword.put(filter_opts, :correlation_id, correlation_id),
        else: filter_opts

    case Stream.filter(state, path, start_timestamp, filter_opts) do
      {:ok, signals} ->
        # Use custom ID if provided, otherwise generate one
        id = custom_id || ID.generate!()
        now = DateTime.utc_now()

        # Convert list of signals to a map keyed by signal ID
        signals_map = Map.new(signals, fn signal -> {signal.id, signal} end)

        # Create the full snapshot data
        snapshot_data = %SnapshotData{
          id: id,
          path: path,
          signals: signals_map,
          created_at: now
        }

        # Create the lightweight reference
        snapshot_ref = %SnapshotRef{
          id: id,
          path: path,
          created_at: now
        }

        # Store the full data in persistent_term
        :persistent_term.put({__MODULE__, id}, snapshot_data)

        # Store only the reference in the state
        new_state = %{state | snapshots: Map.put(state.snapshots, id, snapshot_ref)}
        {:ok, snapshot_ref, new_state}

      {:error, reason} ->
        Logger.warning("Failed to create snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Error creating snapshot: #{Exception.message(error)}")
      {:error, :snapshot_creation_failed}
  end

  @doc """
  Lists all snapshot references in the bus state, sorted by creation time (newest first).
  Returns a list of snapshot references.

  ## Examples

      iex> Snapshot.list(state)
      [%SnapshotRef{}, %SnapshotRef{}]

      iex> Snapshot.list(empty_state)
      []
  """
  @spec list(BusState.t()) :: [SnapshotRef.t()]
  def list(state) do
    dbug("list", state: state)

    # Get all snapshots and sort them by creation time (newest first)
    state.snapshots
    |> Map.values()
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
  end

  @doc """
  Reads a snapshot by its ID.
  Returns {:ok, snapshot_data} if found or {:error, :not_found} if not found.

  ## Examples

      iex> Snapshot.read(state, "snapshot-id")
      {:ok, %SnapshotData{}}

      iex> Snapshot.read(state, "non-existent-id")
      {:error, :not_found}
  """
  @spec read(BusState.t(), String.t()) :: {:ok, SnapshotData.t()} | {:error, :not_found}
  def read(state, snapshot_id) do
    dbug("read", snapshot_id: snapshot_id, state: state)

    with {:ok, _ref} <- Map.fetch(state.snapshots, snapshot_id),
         {:ok, data} <- get_snapshot_data(snapshot_id) do
      {:ok, data}
    else
      :error ->
        Logger.debug("Snapshot not found: #{snapshot_id}")
        {:error, :not_found}
    end
  rescue
    error ->
      Logger.error("Error reading snapshot: #{Exception.message(error)}")
      {:error, :snapshot_read_failed}
  end

  @doc """
  Deletes a snapshot by its ID.
  Removes both the reference from the state and the data from persistent_term.
  Returns {:ok, new_state} on success or {:error, :not_found} if snapshot doesn't exist.

  ## Examples

      iex> Snapshot.delete(state, "snapshot-id")
      {:ok, %BusState{}}

      iex> Snapshot.delete(state, "non-existent-id")
      {:error, :not_found}
  """
  @spec delete(BusState.t(), String.t()) :: {:ok, BusState.t()} | {:error, :not_found}
  def delete(state, snapshot_id) do
    dbug("delete", snapshot_id: snapshot_id, state: state)

    case Map.has_key?(state.snapshots, snapshot_id) do
      true ->
        # Remove from persistent_term
        :persistent_term.erase({__MODULE__, snapshot_id})
        # Remove reference from state
        new_state = %{state | snapshots: Map.delete(state.snapshots, snapshot_id)}
        {:ok, new_state}

      false ->
        Logger.debug("Cannot delete snapshot: not found #{snapshot_id}")
        {:error, :not_found}
    end
  rescue
    error ->
      Logger.error("Error deleting snapshot: #{Exception.message(error)}")
      {:error, :snapshot_deletion_failed}
  end

  @doc """
  Cleans up all snapshots from the bus state.
  Returns {:ok, new_state} with all snapshots removed.

  ## Examples

      iex> Snapshot.cleanup(state)
      {:ok, %BusState{snapshots: %{}}}
  """
  @spec cleanup(BusState.t()) :: {:ok, BusState.t()}
  def cleanup(state) do
    dbug("cleanup", state: state)

    # Delete all snapshots from persistent_term
    Enum.each(state.snapshots, fn {id, _ref} ->
      :persistent_term.erase({__MODULE__, id})
    end)

    # Return state with empty snapshots map
    {:ok, %{state | snapshots: %{}}}
  rescue
    error ->
      Logger.error("Error cleaning up snapshots: #{Exception.message(error)}")
      {:error, :snapshot_cleanup_failed}
  end

  @doc """
  Cleans up snapshots from the bus state based on a filter function.
  The filter function should return true for snapshots that should be removed.
  Returns {:ok, new_state} with filtered snapshots removed.

  ## Examples

      iex> Snapshot.cleanup(state, fn ref -> ref.path == "user.created" end)
      {:ok, %BusState{}}

      iex> Snapshot.cleanup(state, fn ref -> DateTime.compare(ref.created_at, cutoff_time) == :lt end)
      {:ok, %BusState{}}
  """
  @spec cleanup(BusState.t(), (SnapshotRef.t() -> boolean())) :: {:ok, BusState.t()}
  def cleanup(state, filter_fn) when is_function(filter_fn, 1) do
    dbug("cleanup with filter", state: state)

    # Find snapshots to remove based on the filter
    {to_remove, to_keep} =
      state.snapshots
      |> Enum.split_with(fn {_id, ref} -> filter_fn.(ref) end)

    # Delete filtered snapshots from persistent_term
    Enum.each(to_remove, fn {id, _ref} ->
      :persistent_term.erase({__MODULE__, id})
    end)

    # Create new snapshots map with only the kept snapshots
    new_snapshots = Map.new(to_keep)

    # Return state with updated snapshots map
    {:ok, %{state | snapshots: new_snapshots}}
  rescue
    error ->
      Logger.error("Error cleaning up snapshots with filter: #{Exception.message(error)}")
      {:error, :snapshot_cleanup_failed}
  end

  # Private Helpers

  @spec get_snapshot_data(String.t()) :: {:ok, SnapshotData.t()} | :error
  defp get_snapshot_data(snapshot_id) do
    try do
      data = :persistent_term.get({__MODULE__, snapshot_id})
      {:ok, data}
    rescue
      ArgumentError -> :error
    end
  end
end
