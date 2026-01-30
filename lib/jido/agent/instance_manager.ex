defmodule Jido.Agent.InstanceManager do
  @moduledoc """
  Keyed singleton registry with lifecycle management and optional persistence.

  InstanceManager provides a pattern for managing one agent per logical context
  (user session, game room, connection, conversation). This is NOT a pool—each
  key maps to exactly one agent instance. Features:

  - **Keyed singletons** — one agent per key, lookup or start on demand
  - **Automatic lifecycle** — idle timeout with attachment tracking
  - **Optional persistence** — hibernate/thaw with pluggable storage backends
  - **Multiple registries** — different agent types, different configurations

  ## Architecture

  Each instance manager consists of:
  - A `Registry` for unique key → pid lookup
  - A `DynamicSupervisor` for agent lifecycle
  - Optional `Store` for hibernate/thaw persistence

  ## Usage

      # In your supervision tree
      children = [
        Jido.Agent.InstanceManager.child_spec(
          name: :sessions,
          agent: MyApp.SessionAgent,
          idle_timeout: :timer.minutes(15),
          persistence: [
            store: {Jido.Agent.Store.ETS, table: :session_cache}
          ]
        )
      ]

      # At runtime
      {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
      :ok = Jido.AgentServer.attach(pid)  # Track this caller as attached

  ## Options

  - `:name` - Instance manager name (required, atom)
  - `:agent` - Agent module (required)
  - `:idle_timeout` - Time in ms before idle agent hibernates/stops (default: `:infinity`)
  - `:persistence` - Persistence configuration (optional)
    - `:store` - `{StoreModule, opts}` tuple
    - `:key_fun` - Custom key function `(agent_module, agent_id) -> key`
  - `:agent_opts` - Additional options passed to AgentServer

  ## Lifecycle

  1. `get/3` looks up by key in Registry
  2. If not found and persistence enabled, tries to thaw from store
  3. If still not found, starts fresh agent
  4. Callers use `attach/1` to track interest
  5. When all attachments gone, idle timer starts
  6. On idle timeout: hibernate to store (if configured) then stop

  ## Phoenix Integration

      # LiveView mount
      def mount(_params, %{"session_key" => key}, socket) do
        if connected?(socket) do
          {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, key)
          :ok = Jido.AgentServer.attach(pid)
          {:ok, assign(socket, agent_pid: pid)}
        else
          {:ok, socket}
        end
      end
  """

  use Supervisor

  require Logger

  alias Jido.Agent.Persistence

  @type manager_name :: atom()
  @type key :: term()

  # ---------------------------------------------------------------------------
  # Child Spec
  # ---------------------------------------------------------------------------

  @doc """
  Returns a child specification for starting an instance manager under a supervisor.

  ## Options

  - `:name` - Instance manager name (required)
  - `:agent` - Agent module (required)
  - `:idle_timeout` - Idle timeout in ms (default: `:infinity`)
  - `:persistence` - `[store: {Module, opts}]` (optional)
  - `:agent_opts` - Options passed to AgentServer (optional)

  ## Examples

      Jido.Agent.InstanceManager.child_spec(
        name: :sessions,
        agent: MyApp.SessionAgent,
        idle_timeout: :timer.minutes(15)
      )
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @doc false
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: supervisor_name(name))
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    # Store config in persistent_term for fast access
    config = %{
      name: name,
      agent: Keyword.fetch!(opts, :agent),
      idle_timeout: Keyword.get(opts, :idle_timeout, :infinity),
      persistence: Keyword.get(opts, :persistence),
      agent_opts: Keyword.get(opts, :agent_opts, [])
    }

    :persistent_term.put({__MODULE__, name}, config)

    children = [
      {Registry, keys: :unique, name: registry_name(name)},
      {DynamicSupervisor, strategy: :one_for_one, name: dynamic_supervisor_name(name)},
      {Jido.Agent.InstanceManager.Cleanup, name}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc false
  def stop_manager(name) do
    # Clean up persistent_term config when manager stops
    :persistent_term.erase({__MODULE__, name})
    Supervisor.stop(supervisor_name(name))
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Gets or starts an agent by key.

  If an agent for the given key is already running, returns its pid.
  If persistence is configured and a hibernated state exists, thaws it.
  Otherwise starts a fresh agent.

  ## Options

  - `:initial_state` - Initial state for fresh agents (default: `%{}`)

  ## Examples

      {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123")
      {:ok, pid} = Jido.Agent.InstanceManager.get(:sessions, "user-123", initial_state: %{foo: 1})
  """
  @spec get(manager_name(), key(), keyword()) :: {:ok, pid()} | {:error, term()}
  def get(manager, key, opts \\ []) do
    case lookup(manager, key) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        start_agent(manager, key, opts)
    end
  end

  @doc """
  Looks up an agent by key without starting.

  ## Examples

      {:ok, pid} = Jido.Agent.InstanceManager.lookup(:sessions, "user-123")
      :error = Jido.Agent.InstanceManager.lookup(:sessions, "nonexistent")
  """
  @spec lookup(manager_name(), key()) :: {:ok, pid()} | :error
  def lookup(manager, key) do
    case Registry.lookup(registry_name(manager), key) do
      [{pid, _}] ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          :error
        end

      [] ->
        :error
    end
  end

  @doc """
  Stops an agent by key.

  If persistence is configured, the agent will hibernate before stopping.
  Uses a graceful shutdown to ensure the agent's terminate callback runs.

  ## Examples

      :ok = Jido.Agent.InstanceManager.stop(:sessions, "user-123")
      {:error, :not_found} = Jido.Agent.InstanceManager.stop(:sessions, "nonexistent")
  """
  @spec stop(manager_name(), key()) :: :ok | {:error, :not_found}
  def stop(manager, key) do
    case lookup(manager, key) do
      {:ok, pid} ->
        # Use GenServer.stop for graceful shutdown (triggers terminate/2 with :shutdown)
        # This ensures hibernate happens before the process exits
        try do
          GenServer.stop(pid, :shutdown, 5_000)
          :ok
        catch
          :exit, _ -> :ok
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns statistics for an instance manager.

  ## Examples

      %{count: 5, keys: [...]} = Jido.Agent.InstanceManager.stats(:sessions)
  """
  @spec stats(manager_name()) :: %{count: non_neg_integer(), keys: [key()]}
  def stats(manager) do
    entries = Registry.select(registry_name(manager), [{{:"$1", :_, :_}, [], [:"$1"]}])
    %{count: length(entries), keys: entries}
  end

  # ---------------------------------------------------------------------------
  # Internal: Agent Start
  # ---------------------------------------------------------------------------

  defp start_agent(manager, key, opts) do
    config = get_config(manager)

    # Try to thaw from persistence first
    agent_or_nil = maybe_thaw(config, key)

    child_spec = build_child_spec(config, key, agent_or_nil, opts)

    case DynamicSupervisor.start_child(dynamic_supervisor_name(manager), child_spec) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        # Lost race, another process started it
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_child_spec(config, key, agent_or_nil, opts) do
    initial_state = Keyword.get(opts, :initial_state, %{})

    base_opts =
      [
        agent: agent_or_nil || config.agent,
        # When thawing from persistence we pass a struct, so keep the module explicit.
        agent_module: config.agent,
        id: key_to_id(key),
        name: {:via, Registry, {registry_name(config.name), key}},
        # Instance manager lifecycle options
        lifecycle_mod: Jido.AgentServer.Lifecycle.Keyed,
        pool: config.name,
        pool_key: key,
        idle_timeout: config.idle_timeout,
        persistence: config.persistence
      ] ++ config.agent_opts

    # Only add initial_state for fresh agents (not thawed)
    base_opts =
      if agent_or_nil do
        base_opts
      else
        Keyword.put(base_opts, :initial_state, initial_state)
      end

    # Avoid immediate restarts on normal shutdown/idle timeout; allow restarts on crashes.
    Supervisor.child_spec({Jido.AgentServer, base_opts}, restart: :transient)
  end

  defp maybe_thaw(%{persistence: nil}, _key), do: nil

  defp maybe_thaw(%{persistence: persistence, agent: agent_module}, key) do
    case Persistence.thaw(persistence, agent_module, key) do
      {:ok, agent} ->
        Logger.debug("InstanceManager thawed agent for key #{inspect(key)}")
        agent

      :not_found ->
        nil

      {:error, reason} ->
        Logger.warning(
          "InstanceManager failed to thaw agent for key #{inspect(key)}: #{inspect(reason)}"
        )

        nil
    end
  end

  # ---------------------------------------------------------------------------
  # Internal: Helpers
  # ---------------------------------------------------------------------------

  defp get_config(manager) do
    :persistent_term.get({__MODULE__, manager})
  end

  defp key_to_id(key) when is_binary(key), do: key
  defp key_to_id(key), do: inspect(key)

  # ---------------------------------------------------------------------------
  # Internal: Naming
  # ---------------------------------------------------------------------------

  @doc false
  def supervisor_name(manager), do: :"#{__MODULE__}.Supervisor.#{manager}"

  @doc false
  def registry_name(manager), do: :"#{__MODULE__}.Registry.#{manager}"

  @doc false
  def dynamic_supervisor_name(manager), do: :"#{__MODULE__}.DynamicSupervisor.#{manager}"
end
