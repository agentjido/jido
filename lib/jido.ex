defmodule Jido do
  use Supervisor

  alias Jido.Config.Defaults
  alias Jido.RuntimeStore

  @moduledoc """
  自動 (Jido) - An autonomous agent framework for Elixir, built for workflows and
  multi-agent systems.

  ## Quick Start

  Create a Jido supervisor in your application:

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

  Add to your supervision tree:

      children = [MyApp.Jido]

  Start and manage Agents:

      {:ok, pid} = MyApp.Jido.start_agent(MyAgent, id: "agent-1")
      pid = MyApp.Jido.whereis_agent("agent-1")
      agents = MyApp.Jido.list_agents()
      :ok = MyApp.Jido.stop_agent("agent-1")

  ## Core Concepts

  Jido Agents are immutable data structures. The core operation is `cmd/2`:

      {:ok, agent, directives} = MyAgent.cmd(agent, signal)

  - **Agents** — Immutable structs updated through Signals
  - **Actions** — Functions that transform Agent state and may perform work
  - **Directives** — Runtime-owned external effects (signals, processes, etc.)

  Jido keeps Agent decision logic pure. Actions may be pure or effectful.
  Directives are for effects you want the runtime to own. If a step needs a
  result back now to continue reasoning or update state, an effectful action is
  acceptable; if delivery should belong to the runtime or an integration layer,
  return a directive.

  ## For Tests

  Start a unique Jido instance in runtime tests:

      defmodule MyAgentTest do
        use ExUnit.Case, async: true

        setup do
          jido = :"jido_test_#{System.unique_integer([:positive])}"
          {:ok, jido_pid} = start_supervised({Jido, name: jido})
          {:ok, jido: jido, jido_pid: jido_pid}
        end

        test "Agent works", %{jido: jido} do
          {:ok, pid} = Jido.start_agent(jido, MyAgent)
          # ...
        end
      end
  """

  @doc """
  Creates a Jido supervisor module.

  ## Options

    - `:otp_app` - Required. Your application name (e.g., `:my_app`).
    - `:persistence` - Optional `Jido.Persistence.Adapter` module or
      `{module, options}` tuple. The default is no durable persistence.

  ## Example

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app
      end

  Then add to your supervision tree in `lib/my_app/application.ex`:

      children = [MyApp.Jido]

  Optionally configure in `config/config.exs` to customize defaults:

      config :my_app, MyApp.Jido,
        max_tasks: 2000
  """
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    persistence = Keyword.get(opts, :persistence)

    quote location: :keep do
      @otp_app unquote(otp_app)

      @doc false
      @spec __otp_app__() :: unquote(otp_app)
      def __otp_app__, do: @otp_app

      @doc "Returns the optional persistence adapter for this Jido instance."
      @spec __jido_persistence__() :: {module(), keyword()} | nil
      def __jido_persistence__, do: Jido.Persistence.normalize_adapter(unquote(persistence))

      @doc false
      def child_spec(init_arg \\ []) do
        opts =
          config(init_arg)
          |> Keyword.put_new(:name, __MODULE__)
          |> Keyword.put_new(:otp_app, @otp_app)

        Jido.child_spec(opts)
      end

      @doc false
      def start_link(init_arg \\ []) do
        opts =
          config(init_arg)
          |> Keyword.put_new(:name, __MODULE__)
          |> Keyword.put_new(:otp_app, @otp_app)

        Jido.start_link(opts)
      end

      @doc """
      Returns the runtime config for this Jido instance.

      Configuration is loaded from `config :#{@otp_app}, #{inspect(__MODULE__)}` and
      overridden by any runtime options passed in.
      """
      @spec config(keyword()) :: keyword()
      def config(overrides \\ []) do
        @otp_app
        |> Application.get_env(__MODULE__, [])
        |> Keyword.merge(overrides)
      end

      defoverridable config: 1

      @doc "Starts an Agent under this Jido instance."
      @spec start_agent(module() | Jido.Agent.t(), keyword()) ::
              DynamicSupervisor.on_start_child()
      def start_agent(agent, opts \\ []) do
        Jido.start_agent(__MODULE__, agent, opts)
      end

      @doc "Stops an Agent by PID or id under this Jido instance."
      @spec stop_agent(pid() | String.t(), keyword()) :: :ok | {:error, :not_found}
      def stop_agent(pid_or_id, opts \\ []) do
        Jido.stop_agent(__MODULE__, pid_or_id, opts)
      end

      @doc "Looks up an Agent by id under this Jido instance."
      @spec whereis_agent(String.t(), keyword()) :: pid() | nil
      def whereis_agent(id, opts \\ []) do
        Jido.whereis_agent(__MODULE__, id, opts)
      end

      @doc "Lists all Agents under this Jido instance."
      @spec list_agents(keyword()) :: [{String.t(), pid()}]
      def list_agents(opts \\ []), do: Jido.list_agents(__MODULE__, opts)

      @doc "Returns the count of live Agents under this Jido instance."
      @spec agent_count(keyword()) :: non_neg_integer()
      def agent_count(opts \\ []), do: Jido.agent_count(__MODULE__, opts)

      @doc "Persists and stops one live Agent Server."
      def hibernate(server, opts \\ []) do
        Jido.hibernate(__MODULE__, server, opts)
      end

      @doc "Restores and starts one persisted Agent."
      def thaw(agent_module, agent_id, opts \\ []) do
        Jido.thaw(__MODULE__, agent_module, agent_id, opts)
      end

      @doc "Returns the Registry name for this Jido instance."
      @spec registry_name() :: atom()
      def registry_name, do: Jido.registry_name(__MODULE__)

      @doc "Returns the AgentSupervisor name for this Jido instance."
      @spec agent_supervisor_name() :: atom()
      def agent_supervisor_name, do: Jido.agent_supervisor_name(__MODULE__)

      @doc "Returns the TaskSupervisor name for this Jido instance."
      @spec task_supervisor_name() :: atom()
      def task_supervisor_name, do: Jido.task_supervisor_name(__MODULE__)

      @doc "Returns the RuntimeStore name for this Jido instance."
      @spec runtime_store_name() :: atom()
      def runtime_store_name, do: Jido.runtime_store_name(__MODULE__)

      @doc """
      Controls debug mode for this Jido instance.

      - `debug()` — returns current debug level
      - `debug(:on)` — enable developer-friendly verbosity
      - `debug(:verbose)` — enable maximum detail
      - `debug(:off)` — disable debug overrides
      - `debug(pid)` — enable debug mode for one Agent Server
      - `debug(:on, redact: false)` — also disable redaction
      """
      @spec debug() :: Jido.Debug.level()
      def debug, do: Jido.Debug.level(__MODULE__)

      @spec debug(Jido.Debug.level() | pid()) :: :ok | {:error, term()} | Jido.Debug.level()
      def debug(pid) when is_pid(pid), do: Jido.AgentServer.set_debug(pid, true)
      def debug(level) when is_atom(level), do: Jido.Debug.enable(__MODULE__, level)

      @spec debug(Jido.Debug.level(), keyword()) :: :ok
      def debug(level, opts) when is_atom(level), do: Jido.Debug.enable(__MODULE__, level, opts)

      @doc "Returns recent debug events from an Agent Server ring buffer."
      @spec recent(pid(), non_neg_integer()) :: {:ok, [map()]} | {:error, term()}
      def recent(pid, limit \\ 50), do: Jido.AgentServer.recent_events(pid, limit: limit)

      @doc "Returns the current debug status for this instance."
      @spec debug_status() :: map()
      def debug_status, do: Jido.Debug.status(__MODULE__)
    end
  end

  @type agent_id :: String.t() | atom()
  @type partition :: term()

  # Default instance name for scripts/Livebook
  @default_instance Jido.Default

  @doc """
  Returns the default Jido instance name.

  Used by `Jido.start/1` for scripts and Livebook quick-start.
  """
  @spec default_instance() :: atom()
  def default_instance, do: @default_instance

  # ---------------------------------------------------------------------------
  # Debug API (default instance delegates)
  # ---------------------------------------------------------------------------

  @doc """
  Controls debug mode for the default Jido instance (`Jido.Default`).

  - `debug()` — returns current debug level
  - `debug(:on)` — enable developer-friendly verbosity
  - `debug(:verbose)` — enable maximum detail
  - `debug(:off)` — disable debug overrides
  """
  @spec debug() :: Jido.Debug.level()
  def debug, do: Jido.Debug.level(@default_instance)

  @spec debug(Jido.Debug.level()) :: :ok
  def debug(level) when is_atom(level), do: Jido.Debug.enable(@default_instance, level)

  @spec debug(Jido.Debug.level(), keyword()) :: :ok
  def debug(level, opts) when is_atom(level),
    do: Jido.Debug.enable(@default_instance, level, opts)

  @doc """
  Start the default Jido instance for scripts and Livebook.

  This is an idempotent convenience function - safe to call multiple times
  (returns `{:ok, pid}` even if already started).

  ## Examples

      # In a script or Livebook
      {:ok, _} = Jido.start()
      {:ok, pid} = Jido.start_agent(Jido.default_instance(), MyAgent)

      # With custom options
      {:ok, _} = Jido.start(max_tasks: 2000)

  ## Options

  Same as `start_link/1`, but `:name` defaults to `Jido.Default`.
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    opts = Keyword.put_new(opts, :name, @default_instance)

    case start_link(opts) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      other -> other
    end
  end

  @doc """
  Stop a Jido instance.

  Defaults to stopping the default instance (`Jido.Default`).

  ## Examples

      Jido.stop()
      Jido.stop(MyApp.Jido)

  """
  @spec stop(atom()) :: :ok
  def stop(name \\ @default_instance) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  @doc """
  Starts a Jido instance supervisor.

  ## Options
    - `:name` - Required. The name of this Jido instance (e.g., `MyApp.Jido`)

  ## Example

      {:ok, pid} = Jido.start_link(name: MyApp.Jido)
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: Defaults.jido_shutdown_timeout_ms()
    }
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    runtime_store = runtime_store_name(name)

    if otp_app = opts[:otp_app] do
      Jido.Debug.maybe_enable_from_config(otp_app, name)
    end

    :ok = Jido.RuntimeStore.ensure_table(runtime_store)

    base_children = [
      {Task.Supervisor,
       name: task_supervisor_name(name), max_children: Keyword.get(opts, :max_tasks, 1000)},
      {Registry, keys: :unique, name: registry_name(name)},
      {Jido.RuntimeStore, name: runtime_store},
      {Jido.AgentServer.SpawnRegistry, jido: name},
      {DynamicSupervisor,
       name: agent_supervisor_name(name),
       strategy: :one_for_one,
       max_restarts: 1000,
       max_seconds: 5}
    ]

    Supervisor.init(base_children, strategy: :one_for_one)
  end

  @doc """
  Generate a unique identifier.

  Delegates to `Jido.Util.generate_id/0`.
  """
  defdelegate generate_id(), to: Jido.Util

  @doc "Returns the Registry name for a Jido instance."
  @spec registry_name(atom()) :: atom()
  def registry_name(name), do: Module.concat(name, Registry)

  @doc "Returns the AgentSupervisor name for a Jido instance."
  @spec agent_supervisor_name(atom()) :: atom()
  def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

  @doc "Returns the TaskSupervisor name for a Jido instance."
  @spec task_supervisor_name(atom()) :: atom()
  def task_supervisor_name(name), do: Jido.Exec.task_supervisor_name(name)

  @doc "Returns the RuntimeStore name for a Jido instance."
  @spec runtime_store_name(atom()) :: atom()
  def runtime_store_name(name), do: Module.concat(name, RuntimeStore)

  @doc false
  @spec partition_key(term(), partition() | nil) :: term()
  def partition_key(value, nil), do: value
  def partition_key(value, partition), do: {:partition, partition, value}

  @doc false
  @spec unwrap_partition_key(term()) :: {partition() | nil, term()}
  def unwrap_partition_key({:partition, partition, value}), do: {partition, value}
  def unwrap_partition_key(value), do: {nil, value}

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts one Agent under the selected Jido instance supervisor.

  The Agent Server links to its supervisor, not to the calling process. Caller
  exit does not stop the Agent. Use `Jido.AgentServer.start_link/1` when the
  calling process must own that link.

  Options must be a keyword list. An omitted `:id` generates a new identity;
  an explicit ID must be a nonempty string. An existing Agent instance keeps
  its ID and state and rejects instance overrides. A live ID is unique within
  its instance and partition. Starting a duplicate returns an error and leaves
  the existing Agent unchanged.

  This is the standard example startup API. Domain command functions can stay
  in the Agent module; they do not need a matching startup wrapper.
  """
  @spec start_agent(atom(), module() | Jido.Agent.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent(jido_instance, agent, opts \\ []) when is_atom(jido_instance) do
    if is_list(opts) and Keyword.keyword?(opts) do
      opts
      |> Keyword.merge(agent: agent, jido: jido_instance, register: true)
      |> Jido.AgentServer.start()
    else
      {:error,
       Jido.Error.validation_error("Agent startup options must be a keyword list", kind: :config)}
    end
  end

  @doc "Stops one v3 Agent by PID or id."
  @spec stop_agent(atom(), pid() | String.t(), keyword()) :: :ok | {:error, :not_found}
  def stop_agent(jido_instance, pid_or_id, opts \\ [])

  def stop_agent(jido_instance, pid, _opts) when is_atom(jido_instance) and is_pid(pid) do
    Jido.AgentServer.stop(pid)
  catch
    :exit, {:noproc, _details} -> {:error, :not_found}
    :exit, {:normal, _details} -> :ok
  end

  def stop_agent(jido_instance, id, opts)
      when is_atom(jido_instance) and is_binary(id) and is_list(opts) do
    case whereis_agent(jido_instance, id, opts) do
      nil -> {:error, :not_found}
      pid -> stop_agent(jido_instance, pid, opts)
    end
  end

  @doc "Looks up one v3 Agent by id."
  @spec whereis_agent(atom(), String.t(), keyword()) :: pid() | nil
  def whereis_agent(jido_instance, id, opts \\ [])
      when is_atom(jido_instance) and is_binary(id) and is_list(opts) do
    Jido.AgentServer.whereis(
      registry_name(jido_instance),
      id,
      partition: Keyword.get(opts, :partition)
    )
  end

  @doc "Lists all v3 Agents in one Jido instance."
  @spec list_agents(atom(), keyword()) :: [{String.t(), pid()}]
  def list_agents(jido_instance, opts \\ [])
      when is_atom(jido_instance) and is_list(opts) do
    partition = Keyword.get(opts, :partition)

    jido_instance
    |> registry_name()
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.flat_map(fn
      {{:agent, key}, pid} ->
        case unwrap_partition_key(key) do
          {^partition, id} when is_binary(id) -> [{id, pid}]
          {nil, id} when is_nil(partition) and is_binary(id) -> [{id, pid}]
          _other -> []
        end

      _entry ->
        []
    end)
    |> Enum.filter(fn {_id, pid} -> Process.alive?(pid) end)
  end

  @doc "Returns the count of live v3 Agents in one Jido instance."
  @spec agent_count(atom(), keyword()) :: non_neg_integer()
  def agent_count(jido_instance, opts \\ []), do: length(list_agents(jido_instance, opts))

  @doc "Fetches one v3 Agent logical-parent binding."
  @spec agent_parent_binding(atom(), String.t(), keyword()) :: {:ok, map()} | :error
  def agent_parent_binding(jido_instance, child_id, opts \\ []) do
    case RuntimeStore.fetch(
           jido_instance,
           :agent_relationships,
           partition_key(child_id, Keyword.get(opts, :partition))
         ) do
      {:ok, binding} -> normalize_parent_binding(binding)
      :error -> :error
    end
  end

  @doc "Persists and stops one live Agent Server."
  @spec hibernate(atom(), Jido.AgentServer.server(), keyword()) ::
          :ok | {:error, term()}
  def hibernate(jido_instance, server, opts \\ [])
      when is_atom(jido_instance) and is_list(opts) do
    Jido.AgentServer.hibernate(server, opts)
  end

  @doc "Restores and starts one persisted Agent."
  @spec thaw(atom(), module(), String.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def thaw(jido_instance, agent_module, agent_id, opts \\ [])
      when is_atom(jido_instance) and is_atom(agent_module) and is_binary(agent_id) and
             is_list(opts) do
    opts = opts |> Keyword.put(:id, agent_id) |> Keyword.put(:restore, :required)
    start_agent(jido_instance, agent_module, opts)
  end

  defp normalize_parent_binding(%{parent_id: parent_id, tag: _tag} = binding)
       when is_binary(parent_id) do
    {:ok,
     binding
     |> Map.put_new(:parent_partition, nil)
     |> Map.update(:meta, %{}, fn
       meta when is_map(meta) -> meta
       _other -> %{}
     end)}
  end

  defp normalize_parent_binding(_binding), do: :error
end
