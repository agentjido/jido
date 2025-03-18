defmodule Jido.Signal.Topology do
  @moduledoc """
  Provides a data structure for tracking process hierarchies and their states.

  This module supports:
  - Registering processes with their PIDs
  - Establishing parent-child relationships between processes
  - Querying the process hierarchy in various ways
  - Accessing process state through GenServer calls
  """
  use TypedStruct

  typedstruct module: ProcessNode do
    @typedoc "Represents a single process in the hierarchy"
    field(:id, String.t(), enforce: true)
    field(:pid, pid(), enforce: true)
    field(:name, String.t())
    field(:metadata, map(), default: %{})
    field(:parent_id, String.t())
    field(:child_ids, MapSet.t(String.t()), default: MapSet.new())
    field(:registered_at, DateTime.t(), default: DateTime.utc_now())
  end

  typedstruct do
    @typedoc "The complete process hierarchy structure"
    field(:processes, %{String.t() => ProcessNode.t()}, default: %{})
    field(:root_ids, MapSet.t(String.t()), default: MapSet.new())
  end

  @doc """
  Creates a new empty topology.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Registers a new process in the topology.

  ## Parameters
    * topology - The current topology
    * id - Unique identifier for the process
    * pid - Process ID
    * opts - Optional parameters:
      * name - Human-readable name
      * metadata - Additional information
      * parent_id - ID of the parent process (if any)

  ## Returns
    * `{:ok, updated_topology}` - Process was registered successfully
    * `{:error, :already_exists}` - A process with this ID already exists
    * `{:error, :parent_not_found}` - The specified parent ID doesn't exist
  """
  @spec register(t(), String.t(), pid(), keyword()) ::
          {:ok, t()} | {:error, :already_exists | :parent_not_found}
  def register(topology, id, pid, opts \\ []) do
    if Map.has_key?(topology.processes, id) do
      {:error, :already_exists}
    else
      parent_id = Keyword.get(opts, :parent_id)

      # Validate parent exists if specified
      if parent_id && !Map.has_key?(topology.processes, parent_id) do
        {:error, :parent_not_found}
      else
        # Create the process node
        process = %ProcessNode{
          id: id,
          pid: pid,
          name: Keyword.get(opts, :name),
          metadata: Keyword.get(opts, :metadata, %{}),
          parent_id: parent_id
        }

        # Update the topology
        {updated_topology, _} = do_register(topology, process)
        {:ok, updated_topology}
      end
    end
  end

  # Internal implementation for registering a process
  defp do_register(topology, process) do
    # Add the process to the processes map
    topology = put_in(topology.processes[process.id], process)

    if process.parent_id do
      # Update parent's children
      parent = topology.processes[process.parent_id]
      updated_parent = %{parent | child_ids: MapSet.put(parent.child_ids, process.id)}
      topology = put_in(topology.processes[process.parent_id], updated_parent)
      {topology, updated_parent}
    else
      # This is a root process
      topology = update_in(topology.root_ids, &MapSet.put(&1, process.id))
      {topology, process}
    end
  end

  @doc """
  Unregisters a process and all its descendants from the topology.

  ## Parameters
    * topology - The current topology
    * id - ID of the process to remove

  ## Returns
    * `{:ok, updated_topology}` - Process was removed successfully
    * `{:error, :not_found}` - No process with this ID exists
  """
  @spec unregister(t(), String.t()) :: {:ok, t()} | {:error, :not_found}
  def unregister(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        # Remove all descendants first
        topology = remove_descendants(topology, id)

        # Update parent's children list if this has a parent
        topology =
          if process.parent_id do
            parent = topology.processes[process.parent_id]
            updated_parent = %{parent | child_ids: MapSet.delete(parent.child_ids, id)}
            put_in(topology.processes[process.parent_id], updated_parent)
          else
            # Remove from root list if it's a root process
            update_in(topology.root_ids, &MapSet.delete(&1, id))
          end

        # Remove the process itself
        topology = update_in(topology.processes, &Map.delete(&1, id))
        {:ok, topology}

      :error ->
        {:error, :not_found}
    end
  end

  # Recursively remove all descendants of a process
  defp remove_descendants(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        Enum.reduce(process.child_ids, topology, fn child_id, acc ->
          # Recursively remove each child and its descendants
          acc = remove_descendants(acc, child_id)
          # Remove the child itself
          update_in(acc.processes, &Map.delete(&1, child_id))
        end)

      :error ->
        topology
    end
  end

  @doc """
  Establishes a parent-child relationship between two processes.

  ## Parameters
    * topology - The current topology
    * parent_id - ID of the parent process
    * child_id - ID of the child process

  ## Returns
    * `{:ok, updated_topology}` - Relationship established successfully
    * `{:error, :not_found}` - One of the processes doesn't exist
    * `{:error, :cycle_detected}` - This would create a cycle in the hierarchy
  """
  @spec set_parent(t(), String.t(), String.t()) ::
          {:ok, t()} | {:error, :not_found | :cycle_detected}
  def set_parent(topology, parent_id, child_id) do
    with {:ok, parent} <- Map.fetch(topology.processes, parent_id),
         {:ok, child} <- Map.fetch(topology.processes, child_id),
         false <- would_create_cycle?(topology, parent_id, child_id) do
      # Remove from previous parent's children if it had one
      topology =
        if child.parent_id do
          old_parent = topology.processes[child.parent_id]

          updated_old_parent = %{
            old_parent
            | child_ids: MapSet.delete(old_parent.child_ids, child_id)
          }

          put_in(topology.processes[child.parent_id], updated_old_parent)
        else
          # Remove from root list if it was a root process
          update_in(topology.root_ids, &MapSet.delete(&1, child_id))
        end

      # Update parent's children
      updated_parent = %{parent | child_ids: MapSet.put(parent.child_ids, child_id)}
      topology = put_in(topology.processes[parent_id], updated_parent)

      # Update child's parent
      updated_child = %{child | parent_id: parent_id}
      topology = put_in(topology.processes[child_id], updated_child)

      {:ok, topology}
    else
      :error -> {:error, :not_found}
      true -> {:error, :cycle_detected}
    end
  end

  # Check if setting this parent would create a cycle
  defp would_create_cycle?(topology, parent_id, child_id) do
    # A cycle would be created if the child is already an ancestor of the parent
    parent_id == child_id || ancestor?(topology, child_id, parent_id)
  end

  # Check if potential_ancestor is an ancestor of process_id
  defp ancestor?(topology, potential_ancestor, process_id) do
    case Map.fetch(topology.processes, process_id) do
      {:ok, process} ->
        case process.parent_id do
          nil -> false
          ^potential_ancestor -> true
          parent_id -> ancestor?(topology, potential_ancestor, parent_id)
        end

      :error ->
        false
    end
  end

  @doc """
  Returns a list of all processes in the topology.
  """
  @spec list_all(t()) :: [ProcessNode.t()]
  def list_all(topology) do
    Map.values(topology.processes)
  end

  @doc """
  Returns a list of all root processes (those without parents).
  """
  @spec list_roots(t()) :: [ProcessNode.t()]
  def list_roots(topology) do
    topology.root_ids
    |> Enum.map(fn id -> topology.processes[id] end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns a list of all direct children of a process.
  """
  @spec list_children(t(), String.t()) :: [ProcessNode.t()]
  def list_children(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        process.child_ids
        |> Enum.map(fn child_id -> topology.processes[child_id] end)
        |> Enum.reject(&is_nil/1)

      :error ->
        []
    end
  end

  @doc """
  Returns all descendants of a process (children, grandchildren, etc.).
  """
  @spec list_descendants(t(), String.t()) :: [ProcessNode.t()]
  def list_descendants(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        direct_children = list_children(topology, id)

        descendants =
          Enum.flat_map(process.child_ids, fn child_id ->
            list_descendants(topology, child_id)
          end)

        direct_children ++ descendants

      :error ->
        []
    end
  end

  @doc """
  Retrieves state from the GenServer process.

  ## Parameters
    * topology - The current topology
    * id - ID of the process

  ## Returns
    * `{:ok, state}` - State was retrieved successfully
    * `{:error, :not_found}` - No process with this ID exists
    * `{:error, reason}` - GenServer call failed
  """
  @spec get_state(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_state(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        try do
          case GenServer.call(process.pid, :get_state) do
            {:ok, state} -> {:ok, state}
            error -> error
          end
        catch
          :exit, reason -> {:error, reason}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieves states from all processes in the topology.

  ## Returns
    * Map of process IDs to their states
  """
  @spec get_all_states(t()) :: %{String.t() => term()}
  def get_all_states(topology) do
    topology.processes
    |> Enum.map(fn {id, _} -> {id, get_state(topology, id)} end)
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {id, {:ok, state}} -> {id, state} end)
    |> Map.new()
  end

  @doc """
  Retrieves states from all descendants of a process.

  ## Returns
    * Map of process IDs to their states
  """
  @spec get_descendant_states(t(), String.t()) :: %{String.t() => term()}
  def get_descendant_states(topology, id) do
    descendants = list_descendants(topology, id)

    descendants
    |> Enum.map(fn process -> {process.id, get_state(topology, process.id)} end)
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {id, {:ok, state}} -> {id, state} end)
    |> Map.new()
  end

  @doc """
  Returns a tree representation of the hierarchy starting from the given process.
  If no process ID is provided, returns the entire forest from all root processes.

  ## Returns
  A tree structure where each node is a map containing:
    * `:process` - The process node
    * `:state` - The process state (if available)
    * `:children` - A list of child tree nodes
  """
  @spec to_tree(t(), String.t() | nil) :: [map()]
  def to_tree(topology, id \\ nil)

  def to_tree(topology, nil) do
    # Return a forest (list of trees) starting from each root
    topology.root_ids
    |> Enum.map(fn root_id -> build_tree(topology, root_id) end)
    |> Enum.reject(&is_nil/1)
  end

  def to_tree(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, _} -> [build_tree(topology, id)]
      :error -> []
    end
  end

  defp build_tree(topology, id) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        state =
          case get_state(topology, id) do
            {:ok, state} -> state
            _ -> nil
          end

        children =
          process.child_ids
          |> Enum.map(fn child_id -> build_tree(topology, child_id) end)
          |> Enum.reject(&is_nil/1)

        %{process: process, state: state, children: children}

      :error ->
        nil
    end
  end

  @doc """
  Prints a visual representation of the hierarchy to the console.
  If no process ID is provided, prints the entire forest from all root processes.
  """
  @spec print(t(), String.t() | nil) :: :ok
  def print(topology, id \\ nil) do
    tree = to_tree(topology, id)
    print_tree(tree)
    :ok
  end

  defp print_tree(tree, prefix \\ "") do
    Enum.each(tree, fn node ->
      process = node.process
      name = process.name || process.id

      # Print this node
      IO.puts("#{prefix}├── #{name} (#{inspect(process.pid)})")

      # Print children with increased indentation
      child_prefix = "#{prefix}│   "
      print_tree(node.children, child_prefix)
    end)
  end

  @doc """
  Returns the number of processes in the topology.
  """
  @spec count(t()) :: non_neg_integer()
  def count(topology) do
    map_size(topology.processes)
  end

  @doc """
  Updates a process's metadata.

  ## Returns
    * `{:ok, updated_topology}` - Metadata was updated successfully
    * `{:error, :not_found}` - No process with this ID exists
  """
  @spec update_metadata(t(), String.t(), map()) :: {:ok, t()} | {:error, :not_found}
  def update_metadata(topology, id, metadata) do
    case Map.fetch(topology.processes, id) do
      {:ok, process} ->
        updated_process = %{process | metadata: Map.merge(process.metadata, metadata)}
        updated_topology = put_in(topology.processes[id], updated_process)
        {:ok, updated_topology}

      :error ->
        {:error, :not_found}
    end
  end
end
