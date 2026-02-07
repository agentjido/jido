defmodule Jido.Memory.Agent do
  @moduledoc """
  Helper for managing Memory in agent state.

  Memory is stored at the reserved key `:__memory__` in `agent.state`.
  This follows the same pattern as `:__thread__` for thread state and
  `:__strategy__` for strategy state.

  Provides generic space operations only. Domain-specific wrappers
  (world model, task lists, etc.) should be built in your own modules
  on top of these primitives.

  ## Example

      alias Jido.Memory.Agent, as: MemoryAgent

      # Ensure agent has memory
      agent = MemoryAgent.ensure(agent)

      # Work with map spaces
      agent = MemoryAgent.put_in_space(agent, :world, :temperature, 22)
      temp = MemoryAgent.get_in_space(agent, :world, :temperature)

      # Work with list spaces
      agent = MemoryAgent.append_to_space(agent, :tasks, %{id: "t1", text: "Check sensor"})
  """

  alias Jido.Agent
  alias Jido.Memory
  alias Jido.Memory.Space

  @key :__memory__

  # --- Container Operations ---

  @doc "Returns the reserved key for memory storage."
  @spec key() :: atom()
  def key, do: @key

  @doc "Get memory from agent state."
  @spec get(Agent.t(), Memory.t() | nil) :: Memory.t() | nil
  def get(%Agent{state: state}, default \\ nil) do
    Map.get(state, @key, default)
  end

  @doc "Put memory into agent state."
  @spec put(Agent.t(), Memory.t()) :: Agent.t()
  def put(%Agent{} = agent, %Memory{} = memory) do
    %{agent | state: Map.put(agent.state, @key, memory)}
  end

  @doc "Update memory using a function."
  @spec update(Agent.t(), (Memory.t() | nil -> Memory.t())) :: Agent.t()
  def update(%Agent{} = agent, fun) when is_function(fun, 1) do
    current = get(agent)
    put(agent, fun.(current))
  end

  @doc "Ensure agent has memory (initialize if missing)."
  @spec ensure(Agent.t(), keyword()) :: Agent.t()
  def ensure(%Agent{} = agent, opts \\ []) do
    case get(agent) do
      nil -> put(agent, Memory.new(opts))
      _memory -> agent
    end
  end

  @doc "Check if agent has memory."
  @spec has_memory?(Agent.t()) :: boolean()
  def has_memory?(%Agent{} = agent), do: get(agent) != nil

  # --- Space Operations ---

  @doc "Get a space by name."
  @spec space(Agent.t(), atom()) :: Space.t() | nil
  def space(%Agent{} = agent, name) when is_atom(name) do
    case get(agent) do
      nil -> nil
      memory -> Map.get(memory.spaces, name)
    end
  end

  @doc "Put a space by name. Bumps container rev and updated_at."
  @spec put_space(Agent.t(), atom(), Space.t(), keyword()) :: Agent.t()
  def put_space(%Agent{} = agent, name, %Space{} = space, opts \\ []) when is_atom(name) do
    agent = ensure(agent)
    memory = get(agent)
    now = opts[:now] || System.system_time(:millisecond)

    updated_memory = %{
      memory
      | spaces: Map.put(memory.spaces, name, space),
        rev: memory.rev + 1,
        updated_at: now
    }

    put(agent, updated_memory)
  end

  @doc "Update a space using a function. Bumps both space and container revisions."
  @spec update_space(Agent.t(), atom(), (Space.t() -> Space.t()), keyword()) :: Agent.t()
  def update_space(%Agent{} = agent, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) do
    agent = ensure(agent)
    memory = get(agent)

    case Map.get(memory.spaces, name) do
      nil ->
        raise ArgumentError, "space #{inspect(name)} does not exist"

      current_space ->
        updated_space = fun.(current_space)
        updated_space = %{updated_space | rev: updated_space.rev + 1}
        now = opts[:now] || System.system_time(:millisecond)

        updated_memory = %{
          memory
          | spaces: Map.put(memory.spaces, name, updated_space),
            rev: memory.rev + 1,
            updated_at: now
        }

        put(agent, updated_memory)
    end
  end

  @doc "Ensure a space exists with default data. Does not overwrite existing."
  @spec ensure_space(Agent.t(), atom(), map() | list()) :: Agent.t()
  def ensure_space(%Agent{} = agent, name, default_data) when is_atom(name) do
    agent = ensure(agent)

    case space(agent, name) do
      nil ->
        new_space = %Space{data: default_data, rev: 0, metadata: %{}}
        put_space(agent, name, new_space)

      _existing ->
        agent
    end
  end

  @doc "Delete a space. Raises on reserved spaces."
  @spec delete_space(Agent.t(), atom(), keyword()) :: Agent.t()
  def delete_space(%Agent{} = agent, name, opts \\ []) when is_atom(name) do
    if name in Memory.reserved_spaces() do
      raise ArgumentError, "cannot delete reserved space #{inspect(name)}"
    end

    agent = ensure(agent)
    memory = get(agent)
    now = opts[:now] || System.system_time(:millisecond)

    updated_memory = %{
      memory
      | spaces: Map.delete(memory.spaces, name),
        rev: memory.rev + 1,
        updated_at: now
    }

    put(agent, updated_memory)
  end

  @doc "Get the full spaces map."
  @spec spaces(Agent.t()) :: map() | nil
  def spaces(%Agent{} = agent) do
    case get(agent) do
      nil -> nil
      memory -> memory.spaces
    end
  end

  @doc "Check if a space exists."
  @spec has_space?(Agent.t(), atom()) :: boolean()
  def has_space?(%Agent{} = agent, name) when is_atom(name) do
    space(agent, name) != nil
  end

  # --- Map Space Operations ---

  @doc "Get a key from a map space."
  @spec get_in_space(Agent.t(), atom(), term(), term()) :: term()
  def get_in_space(%Agent{} = agent, space_name, key, default \\ nil) do
    case space(agent, space_name) do
      %Space{data: data} when is_map(data) -> Map.get(data, key, default)
      nil -> default
      _ -> raise ArgumentError, "space #{inspect(space_name)} is not a map space"
    end
  end

  @doc "Put a key/value into a map space."
  @spec put_in_space(Agent.t(), atom(), term(), term()) :: Agent.t()
  def put_in_space(%Agent{} = agent, space_name, key, value) do
    agent = ensure(agent)
    validate_map_space!(agent, space_name)

    update_space(agent, space_name, fn space ->
      %{space | data: Map.put(space.data, key, value)}
    end)
  end

  @doc "Delete a key from a map space."
  @spec delete_from_space(Agent.t(), atom(), term()) :: Agent.t()
  def delete_from_space(%Agent{} = agent, space_name, key) do
    agent = ensure(agent)
    validate_map_space!(agent, space_name)

    update_space(agent, space_name, fn space ->
      %{space | data: Map.delete(space.data, key)}
    end)
  end

  # --- List Space Operations ---

  @doc "Append an item to a list space."
  @spec append_to_space(Agent.t(), atom(), term()) :: Agent.t()
  def append_to_space(%Agent{} = agent, space_name, item) do
    agent = ensure(agent)
    validate_list_space!(agent, space_name)

    update_space(agent, space_name, fn space ->
      %{space | data: space.data ++ [item]}
    end)
  end

  # --- Private Helpers ---

  defp validate_map_space!(agent, space_name) do
    case space(agent, space_name) do
      %Space{data: data} when is_map(data) -> :ok
      nil -> raise ArgumentError, "space #{inspect(space_name)} does not exist"
      _ -> raise ArgumentError, "space #{inspect(space_name)} is not a map space"
    end
  end

  defp validate_list_space!(agent, space_name) do
    case space(agent, space_name) do
      %Space{data: data} when is_list(data) -> :ok
      nil -> raise ArgumentError, "space #{inspect(space_name)} does not exist"
      _ -> raise ArgumentError, "space #{inspect(space_name)} is not a list space"
    end
  end
end
