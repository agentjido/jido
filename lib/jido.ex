defmodule Jido do
  use Supervisor

  alias Jido.Agent.Ref
  alias Jido.Instance.{NamespaceRegistry, Options, RefFacade}
  alias Jido.RuntimeStore

  @shutdown_timeout_ms 10_000
  @instance_config_hive :jido_instance_config

  @moduledoc """
  自動 (Jido) - A declarative actor and agent framework for Elixir, built for
  workflows and multi-agent systems.

  ## Quick Start

  Create a Jido supervisor in your application:

      defmodule MyApp.Jido do
        use Jido,
          otp_app: :my_app,
          namespace: "my-app/primary"
      end

  Add to your supervision tree:

      children = [MyApp.Jido]

  Start and manage Agents:

      {:ok, pid} = MyApp.Jido.start_agent(MyAgent, id: "agent-1")
      pid = MyApp.Jido.whereis_agent("agent-1")
      agents = MyApp.Jido.list_agents()
      :ok = MyApp.Jido.stop_agent("agent-1")

  ## Core Concepts

  Declare an Agent definition with its data schema, routes, Plugins, and
  metadata. Then instantiate it with an identity and initial state. Jido Agents
  are immutable data structures. The core operation is `cmd/2`:

      {:ok, agent, directives} = MyAgent.cmd(agent, signal)

  - **Agent definitions** — Declarative descriptions with no identity or state
  - **Agent instances** — Immutable values updated through Signals
  - **Actions** — Functions that transform Agent state and may perform work
  - **Directives** — Runtime-owned external effects (signals, processes, etc.)

  Jido keeps Agent decision logic pure. Actions may be pure or effectful.
  Directives are for effects you want the runtime to own. If a step needs a
  result back now to continue reasoning or update state, an effectful action is
  acceptable; if delivery should belong to the runtime or an integration layer,
  return a directive.

  ## Observe Runtime Work

  Use `Jido.AgentServer.snapshot/2` for the committed Agent and revision. Use
  `Jido.AgentServer.status/2` for current runtime work. A per-Agent debug buffer
  keeps a short diagnostic history when it is enabled.

  `Jido.Telemetry` is the system-wide observation contract. Its semantic event
  catalog supplies Telemetry events, standard metrics, bounded logs, and
  optional OpenTelemetry spans. Instance `debug/1` functions change semantic
  log detail. They do not enable an Agent debug buffer.

  See [Runtime State and Debugging](runtime-state-and-debugging.html) and
  [Telemetry, Tracing, and Logs](telemetry-tracing-and-logs.html).

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
    - `:namespace` - Optional nonempty binary for stable Agent Ref operations.
      One exact namespace can be bound to one live local instance per node.
    - `:persistence` - Optional `Jido.Persistence.Adapter` module or
      `{module, options}` tuple. The default is no durable persistence.

  ## Example

      defmodule MyApp.Jido do
        use Jido, otp_app: :my_app, namespace: "my-app/primary"
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
    namespace = Keyword.get(opts, :namespace)

    quote location: :keep do
      @otp_app unquote(otp_app)

      @doc false
      @spec __otp_app__() :: unquote(otp_app)
      def __otp_app__, do: @otp_app

      @doc "Returns the optional persistence adapter for this Jido instance."
      @spec __jido_persistence__() :: {module(), keyword()} | nil
      def __jido_persistence__, do: Jido.Persistence.normalize_adapter(unquote(persistence))

      @doc "Returns the configured stable namespace for this Jido instance."
      @spec __jido_namespace__() :: String.t() | nil
      def __jido_namespace__, do: unquote(namespace)

      @doc false
      def child_spec(init_arg \\ []) do
        Jido.child_spec(__jido_instance_options__(init_arg))
      end

      @doc false
      def start_link(init_arg \\ []) do
        Jido.start_link(__jido_instance_options__(init_arg))
      end

      @doc """
      Returns the runtime config for this Jido instance.

      Configuration is loaded from `config :#{@otp_app}, #{inspect(__MODULE__)}` and
      overridden by any runtime options passed in.
      """
      @spec config(term()) :: term()
      def config(overrides \\ []) do
        Jido.merge_instance_config(
          Application.get_env(@otp_app, __MODULE__, []),
          overrides
        )
      end

      defoverridable config: 1

      defp __jido_instance_options__(init_arg) do
        Jido.instance_options(
          config(init_arg),
          __MODULE__,
          @otp_app,
          __jido_namespace__(),
          __jido_persistence__()
        )
      end

      # Compatible Agent lifecycle API

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

      # Stable Agent Ref API

      @doc "Builds one stable Agent Ref in this instance namespace."
      @spec agent_ref(String.t(), keyword()) ::
              {:ok, Jido.Agent.Ref.t()} | {:error, Jido.Error.ValidationError.t()}
      def agent_ref(id, opts \\ []), do: Jido.agent_ref(__MODULE__, id, opts)

      @doc "Resolves the current local PID for one stable Agent Ref."
      @spec resolve_agent(Jido.Agent.Ref.t()) :: {:ok, pid()} | {:error, term()}
      def resolve_agent(%Jido.Agent.Ref{} = ref), do: Jido.resolve_agent(__MODULE__, ref)

      @doc "Starts one Agent with an explicit stable Agent Ref."
      @spec start_agent_ref(Jido.Agent.Ref.t(), module() | Jido.Agent.t(), keyword()) ::
              DynamicSupervisor.on_start_child()
      def start_agent_ref(%Jido.Agent.Ref{} = ref, agent, opts \\ []) do
        Jido.start_agent_ref(__MODULE__, ref, agent, opts)
      end

      @doc "Activates one durable Agent with an explicit stable Agent Ref."
      @spec activate_agent(Jido.Agent.Ref.t(), module(), keyword()) ::
              DynamicSupervisor.on_start_child()
      def activate_agent(%Jido.Agent.Ref{} = ref, agent_module, opts \\ []) do
        Jido.activate_agent(__MODULE__, ref, agent_module, opts)
      end

      @doc "Sends one synchronous Signal through a stable Agent Ref."
      @spec call(Jido.Agent.Ref.t(), Jido.Signal.t(), timeout() | keyword()) ::
              Jido.AgentServer.signal_result()
      def call(%Jido.Agent.Ref{} = ref, signal, timeout_or_opts \\ 5_000) do
        Jido.call(__MODULE__, ref, signal, timeout_or_opts)
      end

      @doc "Sends one asynchronous Signal through a stable Agent Ref."
      @spec cast(Jido.Agent.Ref.t(), Jido.Signal.t()) :: :ok | {:error, term()}
      def cast(%Jido.Agent.Ref{} = ref, signal), do: Jido.cast(__MODULE__, ref, signal)

      @doc "Starts one asynchronous Signal request through a stable Agent Ref."
      @spec send_request(Jido.Agent.Ref.t(), Jido.Signal.t(), timeout()) :: term()
      def send_request(%Jido.Agent.Ref{} = ref, signal, timeout \\ 5_000) do
        Jido.send_request(__MODULE__, ref, signal, timeout)
      end

      @doc "Receives an Agent request response with the standard OTP envelope."
      @spec receive_response(term(), timeout()) :: term()
      def receive_response(request_id, timeout \\ 5_000) do
        Jido.receive_response(request_id, timeout)
      end

      @doc "Stops the local Agent resolved by a stable Agent Ref."
      @spec stop_agent_ref(Jido.Agent.Ref.t(), term(), timeout()) ::
              :ok | {:error, term()}
      def stop_agent_ref(%Jido.Agent.Ref{} = ref, reason \\ :shutdown, timeout \\ 5_000) do
        Jido.stop_agent_ref(__MODULE__, ref, reason, timeout)
      end

      @doc "Persists and stops the local Agent resolved by a stable Agent Ref."
      @spec hibernate_ref(Jido.Agent.Ref.t(), keyword()) :: :ok | {:error, term()}
      def hibernate_ref(%Jido.Agent.Ref{} = ref, opts \\ []) do
        Jido.hibernate_ref(__MODULE__, ref, opts)
      end

      @doc "Writes a durable tombstone for one inactive stable Agent Ref."
      @spec delete_agent(Jido.Agent.Ref.t(), module(), keyword()) :: :ok | {:error, term()}
      def delete_agent(%Jido.Agent.Ref{} = ref, agent_module, opts \\ []) do
        Jido.delete_agent(__MODULE__, ref, agent_module, opts)
      end

      @doc "Cancels current pre-commit work for one stable Agent Ref."
      @spec cancel(Jido.Agent.Ref.t(), timeout()) :: :ok | {:error, term()}
      def cancel(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.cancel(__MODULE__, ref, timeout)
      end

      @doc "Cancels one matching Turn for a stable Agent Ref."
      @spec cancel_turn(Jido.Agent.Ref.t(), String.t(), timeout()) ::
              :ok | {:error, term()}
      def cancel_turn(%Jido.Agent.Ref{} = ref, turn_id, timeout \\ 5_000) do
        Jido.cancel_turn(__MODULE__, ref, turn_id, timeout)
      end

      @doc "Attaches an owner process through a stable Agent Ref."
      @spec attach_ref(Jido.Agent.Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
      def attach_ref(%Jido.Agent.Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000) do
        Jido.attach(__MODULE__, ref, owner_pid, timeout)
      end

      @doc "Detaches an owner process through a stable Agent Ref."
      @spec detach_ref(Jido.Agent.Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
      def detach_ref(%Jido.Agent.Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000) do
        Jido.detach(__MODULE__, ref, owner_pid, timeout)
      end

      @doc "Resets the idle timer through a stable Agent Ref."
      @spec touch_ref(Jido.Agent.Ref.t()) :: :ok | {:error, term()}
      def touch_ref(%Jido.Agent.Ref{} = ref), do: Jido.touch(__MODULE__, ref)

      @doc "Returns the committed Agent for one stable Agent Ref."
      @spec agent(Jido.Agent.Ref.t(), timeout()) :: Jido.Agent.t() | {:error, term()}
      def agent(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.agent(__MODULE__, ref, timeout)
      end

      @doc "Returns one Plugin-owned field from the complete Agent state through a stable Ref."
      @spec plugin_state(Jido.Agent.Ref.t(), module(), timeout()) ::
              {:ok, term()} | {:error, term()}
      def plugin_state(%Jido.Agent.Ref{} = ref, plugin, timeout \\ 5_000) do
        Jido.plugin_state(__MODULE__, ref, plugin, timeout)
      end

      @doc "Returns Turn status through a stable Agent Ref."
      @spec status(Jido.Agent.Ref.t(), timeout()) :: map() | {:error, term()}
      def status(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.status(__MODULE__, ref, timeout)
      end

      @doc "Returns a committed snapshot through a stable Agent Ref."
      @spec snapshot(Jido.Agent.Ref.t(), timeout()) :: map() | {:error, term()}
      def snapshot(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.snapshot(__MODULE__, ref, timeout)
      end

      @doc "Returns child runtime status through a stable Agent Ref."
      @spec children(Jido.Agent.Ref.t(), timeout()) :: map() | {:error, term()}
      def children(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.children(__MODULE__, ref, timeout)
      end

      @doc "Waits for runtime readiness through a stable Agent Ref."
      @spec await_ready(Jido.Agent.Ref.t(), timeout()) :: :ok | {:error, term()}
      def await_ready(%Jido.Agent.Ref{} = ref, timeout \\ 5_000) do
        Jido.await_ready(__MODULE__, ref, timeout)
      end

      @doc "Enables or disables one Agent's bounded runtime event buffer."
      @spec set_agent_debug(Jido.Agent.Ref.t(), boolean(), timeout()) ::
              :ok | {:error, term()}
      def set_agent_debug(%Jido.Agent.Ref{} = ref, enabled, timeout \\ 5_000) do
        Jido.set_agent_debug(__MODULE__, ref, enabled, timeout)
      end

      @doc "Returns one Agent's recent runtime events in newest-first order."
      @spec recent_events(Jido.Agent.Ref.t(), keyword(), timeout()) ::
              {:ok, [map()]} | {:error, term()}
      def recent_events(%Jido.Agent.Ref{} = ref, opts \\ [], timeout \\ 5_000) do
        Jido.recent_events(__MODULE__, ref, opts, timeout)
      end

      # Compatible relationship and persistence API

      @doc "Fetches one Agent logical-parent binding under this Jido instance."
      @spec agent_parent_binding(String.t(), keyword()) :: {:ok, map()} | :error
      def agent_parent_binding(child_id, opts \\ []) do
        Jido.agent_parent_binding(__MODULE__, child_id, opts)
      end

      @doc "Persists and stops one live Agent Server."
      def hibernate(server, opts \\ []) do
        Jido.hibernate(__MODULE__, server, opts)
      end

      @doc "Restores and starts one persisted Agent."
      def thaw(agent_module, agent_id, opts \\ []) do
        Jido.thaw(__MODULE__, agent_module, agent_id, opts)
      end

      # Instance service names

      @doc "Returns the Registry name for this Jido instance."
      @spec registry_name() :: atom()
      def registry_name, do: Jido.registry_name(__MODULE__)

      @doc "Returns the stable namespace bound to this live Jido instance."
      @spec namespace() :: String.t() | nil
      def namespace, do: Jido.namespace(__MODULE__)

      @doc "Returns the AgentSupervisor name for this Jido instance."
      @spec agent_supervisor_name() :: atom()
      def agent_supervisor_name, do: Jido.agent_supervisor_name(__MODULE__)

      @doc "Returns the TaskSupervisor name for this Jido instance."
      @spec task_supervisor_name() :: atom()
      def task_supervisor_name, do: Jido.task_supervisor_name(__MODULE__)

      @doc "Returns the RuntimeStore name for this Jido instance."
      @spec runtime_store_name() :: atom()
      def runtime_store_name, do: Jido.runtime_store_name(__MODULE__)

      # Instance debug API

      @doc """
      Controls semantic log detail for this Jido instance.

      - `debug()` — returns current debug level
      - `debug(:on)` — log errors and slow semantic operations
      - `debug(:verbose)` — log all terminal semantic events
      - `debug(:off)` — use the global semantic log configuration

      This function does not control an Agent's bounded event buffer. Use
      `set_agent_debug/3` for that buffer.
      """
      @spec debug() :: Jido.debug_level()
      def debug, do: Jido.Debug.level(__MODULE__)

      @spec debug(Jido.debug_level()) :: :ok
      def debug(level) when is_atom(level), do: Jido.Debug.enable(__MODULE__, level)

      @doc "Returns the semantic log override for this Jido instance."
      @spec debug_status() :: map()
      def debug_status, do: Jido.Debug.status(__MODULE__)
    end
  end

  @type partition :: term()
  @typedoc "Semantic log detail for one Jido instance."
  @type debug_level :: :off | :on | :verbose

  # Default instance name for scripts/Livebook
  @default_instance Jido.Default

  # ---------------------------------------------------------------------------
  # Generated instance configuration
  # ---------------------------------------------------------------------------

  @doc false
  def merge_instance_config(config, overrides) do
    cond do
      not (is_list(config) and Keyword.keyword?(config)) -> config
      not (is_list(overrides) and Keyword.keyword?(overrides)) -> overrides
      true -> Keyword.merge(config, overrides)
    end
  end

  @doc false
  def instance_options(config, name, otp_app, namespace, persistence)

  def instance_options(config, name, otp_app, namespace, persistence) when is_list(config) do
    if Keyword.keyword?(config) do
      # Generated helpers address the instance by its module name.
      config
      |> Keyword.put(:name, name)
      |> Keyword.put_new(:otp_app, otp_app)
      |> Keyword.put_new(:namespace, namespace)
      |> Keyword.put_new(:persistence, persistence)
    else
      config
    end
  end

  def instance_options(config, _name, _otp_app, _namespace, _persistence), do: config

  # ---------------------------------------------------------------------------
  # Default instance
  # ---------------------------------------------------------------------------

  @doc """
  Returns the default Jido instance name.

  Used by `Jido.start/1` for scripts and Livebook quick-start.
  """
  @spec default_instance() :: atom()
  def default_instance, do: @default_instance

  @doc """
  Controls semantic log detail for the default Jido instance (`Jido.Default`).

  - `debug()` — returns current debug level
  - `debug(:on)` — log errors and slow semantic operations
  - `debug(:verbose)` — log all terminal semantic events
  - `debug(:off)` — use the global semantic log configuration

  This function does not control an Agent's bounded event buffer. Use
  `Jido.AgentServer.set_debug/3` for that buffer.
  """
  @spec debug() :: debug_level()
  def debug, do: Jido.Debug.level(@default_instance)

  @spec debug(debug_level()) :: :ok
  def debug(level) when is_atom(level), do: Jido.Debug.enable(@default_instance, level)

  @doc """
  Start the default Jido instance for scripts and Livebook.

  This is an idempotent convenience function - safe to call multiple times
  (returns `{:ok, pid}` even if already started).

  ## Examples

      # In a script or Livebook
      {:ok, _} = Jido.start()
      {:ok, pid} = Jido.start_agent(MyAgent)

      # With custom options
      {:ok, _} = Jido.start(max_tasks: 2000)

  ## Options

  Same as `start_link/1`, but `:name` defaults to `Jido.Default`.
  """
  @spec start(term()) :: {:ok, pid()} | {:error, term()}
  def start(opts \\ []) do
    opts =
      if is_list(opts) and Keyword.keyword?(opts),
        do: Keyword.put_new(opts, :name, @default_instance),
        else: opts

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

  # ---------------------------------------------------------------------------
  # Instance supervisor
  # ---------------------------------------------------------------------------

  @doc """
  Starts a Jido instance supervisor.

  ## Options
    - `:name` - Required. The name of this Jido instance (e.g., `MyApp.Jido`)
    - `:namespace` - Optional nonempty stable namespace for Ref-first functions
    - `:max_tasks` - Task Supervisor child limit; defaults to `1_000`
    - `:persistence` - Optional default persistence adapter

  ## Example

      {:ok, pid} = Jido.start_link(name: MyApp.Jido)
  """
  def start_link(opts) do
    with {:ok, opts} <- Options.validate(opts),
         {:ok, claim} <-
           NamespaceRegistry.claim(Keyword.get(opts, :namespace), Keyword.fetch!(opts, :name)) do
      result =
        Supervisor.start_link(
          __MODULE__,
          {opts, claim},
          name: Keyword.fetch!(opts, :name)
        )

      if not match?({:ok, _pid}, result), do: NamespaceRegistry.release(claim)
      result
    end
  end

  @doc false
  def child_spec(opts) do
    opts = Options.validate!(opts)
    name = Keyword.fetch!(opts, :name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: @shutdown_timeout_ms
    }
  end

  @impl true
  def init({opts, claim}) do
    name = Keyword.fetch!(opts, :name)
    runtime_store = runtime_store_name(name)

    with :ok <-
           NamespaceRegistry.bind(claim, Keyword.get(opts, :namespace), name, self()) do
      Jido.Debug.configure(name, opts[:debug])

      :ok = Jido.RuntimeStore.ensure_table(runtime_store)

      true =
        :ets.insert(
          runtime_store,
          {{@instance_config_hive, :persistence}, Keyword.get(opts, :persistence)}
        )

      base_children = [
        {Task.Supervisor,
         name: task_supervisor_name(name), max_children: Keyword.fetch!(opts, :max_tasks)},
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
    else
      {:error, reason} -> exit(reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Instance runtime names and metadata
  # ---------------------------------------------------------------------------

  @doc """
  Generate a UUID7 identifier.

  Delegates to `Jido.Signal.ID.generate!/0`.
  """
  @spec generate_id() :: Jido.Signal.ID.uuid7()
  defdelegate generate_id(), to: Jido.Signal.ID, as: :generate!

  @doc "Returns the Registry name for the default Jido instance."
  @spec registry_name() :: atom()
  def registry_name, do: registry_name(@default_instance)

  @doc "Returns the Registry name for the selected Jido instance."
  @spec registry_name(atom()) :: atom()
  def registry_name(name), do: Module.concat(name, Registry)

  @doc "Returns the stable namespace bound to one live Jido instance."
  @spec namespace(atom() | nil) :: String.t() | nil
  def namespace(nil), do: nil
  def namespace(name), do: NamespaceRegistry.namespace(name)

  @doc false
  @spec instance_persistence(atom()) :: term()
  def instance_persistence(name) when is_atom(name) do
    table = runtime_store_name(name)

    case :ets.lookup(table, {@instance_config_hive, :persistence}) do
      [{{@instance_config_hive, :persistence}, persistence}] -> persistence
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Returns the AgentSupervisor name for the default Jido instance."
  @spec agent_supervisor_name() :: atom()
  def agent_supervisor_name, do: agent_supervisor_name(@default_instance)

  @doc "Returns the AgentSupervisor name for the selected Jido instance."
  @spec agent_supervisor_name(atom()) :: atom()
  def agent_supervisor_name(name), do: Module.concat(name, AgentSupervisor)

  @doc "Returns the TaskSupervisor name for the default Jido instance."
  @spec task_supervisor_name() :: atom()
  def task_supervisor_name, do: task_supervisor_name(@default_instance)

  @doc "Returns the TaskSupervisor name for the selected Jido instance."
  @spec task_supervisor_name(atom() | nil) :: atom()
  def task_supervisor_name(nil), do: Jido.Exec.TaskSupervisor
  def task_supervisor_name(name) when is_atom(name), do: Module.concat(name, TaskSupervisor)

  def task_supervisor_name(name) do
    raise ArgumentError, "Jido instance must be an atom or nil, got: #{inspect(name)}"
  end

  @doc "Returns the RuntimeStore name for the default Jido instance."
  @spec runtime_store_name() :: atom()
  def runtime_store_name, do: runtime_store_name(@default_instance)

  @doc "Returns the RuntimeStore name for the selected Jido instance."
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
  # Stable Agent Ref facade
  # ---------------------------------------------------------------------------

  @doc "Builds one stable Agent Ref in the selected instance namespace."
  @spec agent_ref(atom(), String.t(), keyword()) ::
          {:ok, Ref.t()} | {:error, Jido.Error.ValidationError.t()}
  def agent_ref(instance, id, opts \\ []),
    do: RefFacade.build_ref(instance, id, opts)

  @doc "Resolves the current local PID for one stable Agent Ref."
  @spec resolve_agent(atom(), Ref.t()) :: {:ok, pid()} | {:error, term()}
  def resolve_agent(instance, %Ref{} = ref), do: RefFacade.resolve(instance, ref)

  @doc "Starts one Agent with an explicit stable Agent Ref."
  @spec start_agent_ref(atom(), Ref.t(), module() | Jido.Agent.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent_ref(instance, %Ref{} = ref, agent, opts \\ []),
    do: RefFacade.start_agent(instance, ref, agent, opts)

  @doc "Activates one durable Agent with an explicit stable Agent Ref."
  @spec activate_agent(atom(), Ref.t(), module(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def activate_agent(instance, %Ref{} = ref, agent_module, opts \\ []),
    do: RefFacade.activate_agent(instance, ref, agent_module, opts)

  @doc "Sends one synchronous Signal through a stable Agent Ref."
  @spec call(atom(), Ref.t(), Jido.Signal.t(), timeout() | keyword()) ::
          Jido.AgentServer.signal_result()
  def call(instance, %Ref{} = ref, signal, timeout_or_opts \\ 5_000),
    do: RefFacade.call(instance, ref, signal, timeout_or_opts)

  @doc "Sends one best-effort asynchronous Signal through a stable Agent Ref."
  @spec cast(atom(), Ref.t(), Jido.Signal.t()) :: :ok | {:error, term()}
  def cast(instance, %Ref{} = ref, signal), do: RefFacade.cast(instance, ref, signal)

  @doc "Starts one asynchronous Signal request through a stable Agent Ref."
  @spec send_request(atom(), Ref.t(), Jido.Signal.t(), timeout()) :: term()
  def send_request(instance, %Ref{} = ref, signal, timeout \\ 5_000),
    do: RefFacade.send_request(instance, ref, signal, timeout)

  @doc "Receives an Agent request response with the standard OTP envelope."
  @spec receive_response(term(), timeout()) :: term()
  defdelegate receive_response(request_id, timeout \\ 5_000), to: Jido.AgentServer

  @doc "Stops the local Agent resolved by a stable Agent Ref."
  @spec stop_agent_ref(atom(), Ref.t(), term(), timeout()) :: :ok | {:error, term()}
  def stop_agent_ref(instance, %Ref{} = ref, reason \\ :shutdown, timeout \\ 5_000),
    do: RefFacade.stop(instance, ref, reason, timeout)

  @doc "Persists and stops the local Agent resolved by a stable Agent Ref."
  @spec hibernate_ref(atom(), Ref.t(), keyword()) :: :ok | {:error, term()}
  def hibernate_ref(instance, %Ref{} = ref, opts \\ []),
    do: RefFacade.hibernate(instance, ref, opts)

  @doc "Writes a durable tombstone for one inactive stable Agent Ref."
  @spec delete_agent(atom(), Ref.t(), module(), keyword()) :: :ok | {:error, term()}
  def delete_agent(instance, %Ref{} = ref, agent_module, opts \\ []),
    do: RefFacade.delete(instance, ref, agent_module, opts)

  @doc "Cancels current pre-commit work for one stable Agent Ref."
  @spec cancel(atom(), Ref.t(), timeout()) :: :ok | {:error, term()}
  def cancel(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.cancel(instance, ref, timeout)

  @doc "Cancels one matching Turn for a stable Agent Ref."
  @spec cancel_turn(atom(), Ref.t(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(instance, %Ref{} = ref, turn_id, timeout \\ 5_000),
    do: RefFacade.cancel_turn(instance, ref, turn_id, timeout)

  @doc "Attaches an owner process through a stable Agent Ref."
  @spec attach(atom(), Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000),
    do: RefFacade.attach(instance, ref, owner_pid, timeout)

  @doc "Detaches an owner process through a stable Agent Ref."
  @spec detach(atom(), Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000),
    do: RefFacade.detach(instance, ref, owner_pid, timeout)

  @doc "Resets the idle timer through a stable Agent Ref."
  @spec touch(atom(), Ref.t()) :: :ok | {:error, term()}
  def touch(instance, %Ref{} = ref), do: RefFacade.touch(instance, ref)

  @doc "Returns the committed Agent through a stable Agent Ref."
  @spec agent(atom(), Ref.t(), timeout()) :: Jido.Agent.t() | {:error, term()}
  def agent(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.agent(instance, ref, timeout)

  @doc "Returns one Plugin-owned field from the complete Agent state through a stable Ref."
  @spec plugin_state(atom(), Ref.t(), module(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def plugin_state(instance, %Ref{} = ref, plugin, timeout \\ 5_000),
    do: RefFacade.plugin_state(instance, ref, plugin, timeout)

  @doc "Returns Turn status through a stable Agent Ref."
  @spec status(atom(), Ref.t(), timeout()) :: map() | {:error, term()}
  def status(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.status(instance, ref, timeout)

  @doc "Returns a committed snapshot through a stable Agent Ref."
  @spec snapshot(atom(), Ref.t(), timeout()) :: map() | {:error, term()}
  def snapshot(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.snapshot(instance, ref, timeout)

  @doc "Returns child runtime status through a stable Agent Ref."
  @spec children(atom(), Ref.t(), timeout()) :: map() | {:error, term()}
  def children(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.children(instance, ref, timeout)

  @doc "Waits for runtime readiness through a stable Agent Ref."
  @spec await_ready(atom(), Ref.t(), timeout()) :: :ok | {:error, term()}
  def await_ready(instance, %Ref{} = ref, timeout \\ 5_000),
    do: RefFacade.await_ready(instance, ref, timeout)

  @doc "Enables or disables one Agent's bounded runtime event buffer."
  @spec set_agent_debug(atom(), Ref.t(), boolean(), timeout()) :: :ok | {:error, term()}
  def set_agent_debug(instance, %Ref{} = ref, enabled, timeout \\ 5_000),
    do: RefFacade.set_debug(instance, ref, enabled, timeout)

  @doc "Returns one Agent's recent runtime events in newest-first order."
  @spec recent_events(atom(), Ref.t(), keyword(), timeout()) ::
          {:ok, [map()]} | {:error, term()}
  def recent_events(instance, %Ref{} = ref, opts \\ [], timeout \\ 5_000),
    do: RefFacade.recent_events(instance, ref, opts, timeout)

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts one Agent under the default or selected Jido instance supervisor.

  The one-argument form uses the default instance started by `Jido.start/1`:

      {:ok, _jido} = Jido.start()
      agent = MyAgent.new!(id: "agent-1")
      {:ok, server} = Jido.start_agent(agent)

  Pass an instance as the first argument when the application runs more than
  one Jido supervisor:

      {:ok, server} = Jido.start_agent(MyApp.Jido, agent)

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
  @spec start_agent(module() | Jido.Agent.t()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent), do: start_agent(@default_instance, agent, [])

  @doc """
  Starts an Agent with options in the default instance, or starts an Agent in
  the selected instance with default options.
  """
  @spec start_agent(module() | Jido.Agent.t(), keyword() | module() | Jido.Agent.t()) ::
          DynamicSupervisor.on_start_child()
  def start_agent(agent, opts) when is_list(opts),
    do: start_agent(@default_instance, agent, opts)

  def start_agent(instance, agent) when is_atom(instance),
    do: start_agent(instance, agent, [])

  @doc "Starts an Agent with options in the selected Jido instance."
  @spec start_agent(atom(), module() | Jido.Agent.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent(instance, agent, opts) when is_atom(instance) do
    if is_list(opts) and Keyword.keyword?(opts) do
      opts
      |> Keyword.merge(agent: agent, jido: instance, register: true)
      |> Jido.AgentServer.start()
    else
      {:error,
       Jido.Error.validation_error("Agent startup options must be a keyword list", kind: :config)}
    end
  end

  @doc "Stops one Agent under the default Jido instance."
  @spec stop_agent(Jido.AgentServer.server() | String.t()) :: :ok | {:error, :not_found}
  def stop_agent(pid_or_id), do: stop_agent(@default_instance, pid_or_id, [])

  @doc """
  Stops an Agent with options in the default instance, or stops an Agent in
  the selected instance with default options.
  """
  @spec stop_agent(
          atom() | Jido.AgentServer.server() | String.t(),
          keyword() | Jido.AgentServer.server() | String.t()
        ) ::
          :ok | {:error, :not_found}
  def stop_agent(pid_or_id, opts) when is_list(opts),
    do: stop_agent(@default_instance, pid_or_id, opts)

  def stop_agent(instance, pid_or_id) when is_atom(instance),
    do: stop_agent(instance, pid_or_id, [])

  @doc "Stops an Agent with options in the selected Jido instance."
  @spec stop_agent(atom(), Jido.AgentServer.server() | String.t(), keyword()) ::
          :ok | {:error, :not_found}
  def stop_agent(instance, pid_or_id, opts)

  def stop_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    case whereis_agent(instance, id, opts) do
      nil -> {:error, :not_found}
      pid -> stop_agent(instance, pid, opts)
    end
  end

  def stop_agent(instance, server, opts)
      when is_atom(instance) and is_list(opts) do
    with {:ok, pid} <- owned_agent_server(instance, server, opts) do
      Jido.AgentServer.stop(pid)
    end
  catch
    :exit, :noproc -> {:error, :not_found}
    :exit, {:noproc, _details} -> {:error, :not_found}
    :exit, {:normal, _details} -> :ok
  end

  @doc "Looks up one Agent by id under the default Jido instance."
  @spec whereis_agent(String.t()) :: pid() | nil
  def whereis_agent(id), do: whereis_agent(@default_instance, id, [])

  @doc """
  Looks up an Agent with options in the default instance, or looks up an Agent
  in the selected instance with default options.
  """
  @spec whereis_agent(atom() | String.t(), keyword() | String.t()) :: pid() | nil
  def whereis_agent(id, opts) when is_binary(id) and is_list(opts),
    do: whereis_agent(@default_instance, id, opts)

  def whereis_agent(instance, id) when is_atom(instance),
    do: whereis_agent(instance, id, [])

  @doc "Looks up an Agent with options in the selected Jido instance."
  @spec whereis_agent(atom(), String.t(), keyword()) :: pid() | nil
  def whereis_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    Jido.AgentServer.whereis(
      registry_name(instance),
      id,
      partition: Keyword.get(opts, :partition)
    )
  end

  @doc "Lists all Agents in the default Jido instance."
  @spec list_agents() :: [{String.t(), pid()}]
  def list_agents, do: list_agents(@default_instance, [])

  @doc "Lists Agents with default-instance options, or lists a selected instance."
  @spec list_agents(keyword() | atom()) :: [{String.t(), pid()}]
  def list_agents(opts) when is_list(opts), do: list_agents(@default_instance, opts)
  def list_agents(instance) when is_atom(instance), do: list_agents(instance, [])

  @doc "Lists Agents with options in the selected Jido instance."
  @spec list_agents(atom(), keyword()) :: [{String.t(), pid()}]
  def list_agents(instance, opts)
      when is_atom(instance) and is_list(opts) do
    partition = Keyword.get(opts, :partition)

    instance
    |> registry_name()
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
    |> Enum.flat_map(fn
      {{:agent, key}, pid, :ready} ->
        case unwrap_partition_key(key) do
          {^partition, id} when is_binary(id) -> [{id, pid}]
          _other -> []
        end

      _entry ->
        []
    end)
    |> Enum.filter(fn {_id, pid} -> Process.alive?(pid) end)
  end

  @doc "Returns the count of live Agents in the default Jido instance."
  @spec agent_count() :: non_neg_integer()
  def agent_count, do: agent_count(@default_instance, [])

  @doc "Counts Agents with default-instance options, or counts a selected instance."
  @spec agent_count(keyword() | atom()) :: non_neg_integer()
  def agent_count(opts) when is_list(opts), do: agent_count(@default_instance, opts)
  def agent_count(instance) when is_atom(instance), do: agent_count(instance, [])

  @doc "Counts live Agents with options in the selected Jido instance."
  @spec agent_count(atom(), keyword()) :: non_neg_integer()
  def agent_count(instance, opts), do: length(list_agents(instance, opts))

  @doc "Fetches one Agent logical-parent binding from the default instance."
  @spec agent_parent_binding(String.t()) :: {:ok, map()} | :error
  def agent_parent_binding(child_id),
    do: agent_parent_binding(@default_instance, child_id, [])

  @doc """
  Fetches a parent binding with default-instance options, or fetches it from a
  selected instance with default options.
  """
  @spec agent_parent_binding(atom() | String.t(), keyword() | String.t()) ::
          {:ok, map()} | :error
  def agent_parent_binding(child_id, opts) when is_binary(child_id) and is_list(opts),
    do: agent_parent_binding(@default_instance, child_id, opts)

  def agent_parent_binding(instance, child_id) when is_atom(instance),
    do: agent_parent_binding(instance, child_id, [])

  @doc "Fetches a parent binding with options from the selected Jido instance."
  @spec agent_parent_binding(atom(), String.t(), keyword()) :: {:ok, map()} | :error
  def agent_parent_binding(instance, child_id, opts)
      when is_atom(instance) and is_binary(child_id) and is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, binding} <-
           RuntimeStore.fetch(
             instance,
             :agent_relationships,
             partition_key(child_id, Keyword.get(opts, :partition))
           ) do
      normalize_parent_binding(binding)
    else
      _reason -> :error
    end
  end

  def agent_parent_binding(_instance, _child_id, _opts), do: :error

  @doc "Persists and stops one live Agent Server in the default instance."
  @spec hibernate(Jido.AgentServer.server()) :: :ok | {:error, term()}
  def hibernate(server), do: hibernate(@default_instance, server, [])

  @doc """
  Hibernates an Agent with default-instance options, or hibernates it in a
  selected instance with default options.
  """
  @spec hibernate(Jido.AgentServer.server(), keyword() | Jido.AgentServer.server()) ::
          :ok | {:error, term()}
  def hibernate(server, opts) when is_list(opts),
    do: hibernate(@default_instance, server, opts)

  def hibernate(instance, server) when is_atom(instance),
    do: hibernate(instance, server, [])

  @doc "Hibernates an Agent with options in the selected Jido instance."
  @spec hibernate(atom(), Jido.AgentServer.server(), keyword()) ::
          :ok | {:error, term()}
  def hibernate(instance, server, opts)
      when is_atom(instance) and is_list(opts) do
    with {:ok, pid} <- owned_agent_server(instance, server, opts) do
      Jido.AgentServer.hibernate(pid, opts)
    end
  end

  @doc "Restores and starts one persisted Agent in the default instance."
  @spec thaw(module(), String.t()) :: DynamicSupervisor.on_start_child()
  def thaw(agent_module, agent_id),
    do: thaw(@default_instance, agent_module, agent_id, [])

  @doc """
  Thaws an Agent with default-instance options, or thaws it in a selected
  instance with default options.
  """
  @spec thaw(module(), module() | String.t(), keyword() | String.t()) ::
          DynamicSupervisor.on_start_child()
  def thaw(agent_module, agent_id, opts)
      when is_atom(agent_module) and is_binary(agent_id) and is_list(opts),
      do: thaw(@default_instance, agent_module, agent_id, opts)

  def thaw(instance, agent_module, agent_id)
      when is_atom(instance) and is_atom(agent_module) and is_binary(agent_id),
      do: thaw(instance, agent_module, agent_id, [])

  @doc "Thaws an Agent with options in the selected Jido instance."
  @spec thaw(atom(), module(), String.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def thaw(instance, agent_module, agent_id, opts)
      when is_atom(instance) and is_atom(agent_module) and is_binary(agent_id) and
             is_list(opts) do
    opts = opts |> Keyword.put(:id, agent_id) |> Keyword.put(:restore, :required)
    start_agent(instance, agent_module, opts)
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

  defp owned_agent_server(instance, server, opts) do
    with true <- not is_nil(instance),
         true <- Keyword.keyword?(opts),
         pid when is_pid(pid) <- safe_whereis(server),
         {:ok, %{agent_id: agent_id, partition: partition}} <-
           Jido.AgentServer.creation_info(pid),
         true <- partition_matches?(opts, partition),
         ^pid <- owned_registry_pid(instance, agent_id, partition, pid) do
      {:ok, pid}
    else
      _reason -> {:error, :not_found}
    end
  end

  defp safe_whereis(server) do
    GenServer.whereis(server)
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp partition_matches?(opts, partition) do
    not Keyword.has_key?(opts, :partition) or Keyword.get(opts, :partition) == partition
  end

  defp owned_registry_pid(instance, agent_id, partition, pid)
       when node(pid) == node() do
    whereis_agent(instance, agent_id, partition: partition)
  end

  defp owned_registry_pid(instance, agent_id, partition, pid) do
    :erpc.call(
      node(pid),
      __MODULE__,
      :whereis_agent,
      [instance, agent_id, [partition: partition]],
      1_000
    )
  catch
    _kind, _reason -> nil
  end
end
