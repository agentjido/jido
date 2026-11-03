defmodule Jido do
  use Supervisor

  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Instance.{Names, NamespaceRegistry, Options, RuntimeStore}

  @shutdown_timeout_ms 10_000

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

  Use `Jido.AgentServer.agent/2` for the committed Agent. Use
  `Jido.AgentServer.status/2` for the revision and current runtime work. Use
  `Jido.AgentServer.history/1` for bounded Turn history.

  `Jido.Telemetry` is the system-wide observation contract. Its semantic event
  catalog supplies Telemetry events, standard metrics, bounded logs, and
  optional OpenTelemetry spans. Instance `debug/1` functions change semantic
  log detail.

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
    - `:namespace` - Nonempty binary for stable Agent Ref operations.
      Required for persistent Agents.
      One exact namespace can be bound to one live local instance per node.
    - `:persistence` - Optional `Jido.Persistence.Store` module or
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
    opts = Options.validate_definition!(opts)
    otp_app = Keyword.fetch!(opts, :otp_app)
    persistence = Keyword.get(opts, :persistence)
    namespace = Keyword.get(opts, :namespace)

    quote location: :keep do
      @otp_app unquote(otp_app)

      @doc false
      @spec __jido_persistence__() :: {module(), keyword()} | nil
      def __jido_persistence__, do: Jido.Persistence.Store.normalize_adapter(unquote(persistence))

      @doc false
      @spec child_spec(term()) :: Supervisor.child_spec()
      def child_spec(init_arg \\ []) do
        Jido.child_spec(__jido_instance_options__(init_arg))
      end

      @doc false
      @spec start_link(term()) :: Supervisor.on_start()
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
        Jido.Instance.Options.merge_definition(
          Application.get_env(@otp_app, __MODULE__, []),
          overrides
        )
      end

      defoverridable config: 1

      defp __jido_instance_options__(init_arg) do
        Jido.Instance.Options.materialize(
          config(init_arg),
          __MODULE__,
          @otp_app,
          unquote(namespace),
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

      @doc "Submits one AgentServer turn through a stable Agent Ref."
      @spec submit(Jido.Agent.Ref.t(), Jido.Signal.t(), keyword()) ::
              Jido.AgentServer.pending() | {:error, term()}
      def submit(%Jido.Agent.Ref{} = ref, signal, opts \\ []),
        do: Jido.submit(__MODULE__, ref, signal, opts)

      @doc "Collects an AgentServer pending reply in its submitting process."
      @spec await(Jido.AgentServer.pending(), timeout()) :: Jido.AgentServer.signal_result()
      def await(pending, timeout \\ 5_000), do: Jido.await(pending, timeout)

      @doc "Discards an AgentServer pending reply without cancelling its turn."
      @spec abandon(Jido.AgentServer.pending()) :: :ok | {:error, term()}
      def abandon(pending), do: Jido.abandon(pending)

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

      # Compatible relationship and persistence API

      @doc "Persists and stops one live Agent Server."
      @spec hibernate(Jido.AgentServer.server(), keyword()) :: :ok | {:error, term()}
      def hibernate(server, opts \\ []) do
        Jido.hibernate(__MODULE__, server, opts)
      end

      @doc "Restores and starts one persisted Agent."
      @spec thaw(module(), String.t(), keyword()) :: DynamicSupervisor.on_start_child()
      def thaw(agent_module, agent_id, opts \\ []) do
        Jido.thaw(__MODULE__, agent_module, agent_id, opts)
      end

      # Instance service names

      # Instance debug API

      @doc """
      Controls semantic log detail for this Jido instance.

      - `debug()` — returns current debug level
      - `debug(:on)` — log errors and slow semantic operations
      - `debug(:verbose)` — log all terminal semantic events
      - `debug(:off)` — use the global semantic log configuration

      """
      @spec debug() :: Jido.debug_level()
      def debug, do: Jido.Telemetry.debug_level(__MODULE__)

      @spec debug(Jido.debug_level()) :: :ok
      def debug(level) when is_atom(level), do: Jido.Telemetry.set_debug(__MODULE__, level)

      @doc "Returns the semantic log override for this Jido instance."
      @spec debug_status() :: map()
      def debug_status, do: Jido.Telemetry.debug_status(__MODULE__)
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

  Set `debug: true` at Agent startup to enable its bounded history buffer.
  Read that buffer with `Jido.AgentServer.history/1`.
  """
  @spec debug() :: debug_level()
  def debug, do: Jido.Telemetry.debug_level(@default_instance)

  @spec debug(debug_level()) :: :ok
  def debug(level) when is_atom(level), do: Jido.Telemetry.set_debug(@default_instance, level)

  @doc """
  Start the default Jido instance for scripts and Livebook.

  This is an idempotent convenience function - safe to call multiple times
  (returns `{:ok, pid}` even if already started).
  Options apply only to the first successful start. A later call returns the
  running instance PID and does not change its namespace, persistence source,
  Task limit, or other configuration. Stop the instance before starting it
  with new options.

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
    - `:namespace` - Nonempty stable namespace for Ref-first functions.
      Required for persistent Agents.
    - `:max_tasks` - Task Supervisor child limit; defaults to `1_000`
    - `:persistence` - Optional default persistence adapter
    - `:agent_server` - Optional AgentServer runtime defaults

  ## Example

      {:ok, pid} = Jido.start_link(name: MyApp.Jido)
  """
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(opts) do
    with {:ok, opts} <- Options.validate(opts),
         :ok <- await_previous_children(Keyword.fetch!(opts, :name)),
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

  defp await_previous_children(name) do
    if Process.whereis(name) do
      :ok
    else
      names = [
        Names.exec_runner(name),
        Names.task_supervisor(name),
        Names.registration_guard(name),
        Names.registry(name),
        Names.runtime_store(name),
        Names.agent_supervisor(name)
      ]

      monitors =
        for child_name <- names,
            pid = Process.whereis(child_name),
            is_pid(pid),
            do: {pid, Process.monitor(pid)}

      deadline = System.monotonic_time(:millisecond) + @shutdown_timeout_ms

      result =
        Enum.reduce_while(monitors, :ok, fn {pid, ref}, :ok ->
          remaining = max(deadline - System.monotonic_time(:millisecond), 0)

          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> {:cont, :ok}
          after
            remaining -> {:halt, {:error, {:previous_instance_still_stopping, pid}}}
          end
        end)

      for {_pid, ref} <- monitors, do: Process.demonitor(ref, [:flush])
      result
    end
  end

  @doc false
  @spec child_spec(term()) :: Supervisor.child_spec()
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
    runtime_store = Names.runtime_store(name)

    with :ok <-
           NamespaceRegistry.bind(claim, Keyword.get(opts, :namespace), name, self()) do
      Jido.Telemetry.configure_debug(name, opts[:debug])

      :ok = RuntimeStore.ensure_table(runtime_store)

      :ok =
        RuntimeStore.put_instance_config(
          runtime_store,
          Keyword.get(opts, :persistence),
          Keyword.get(opts, :agent_server, [])
        )

      base_children = [
        {Runic.Runner,
         name: Names.exec_runner(name), store: Jido.Persistence.ContinuationStore, store_opts: [jido: name]},
        {Task.Supervisor, name: Names.task_supervisor(name), max_children: Keyword.fetch!(opts, :max_tasks)},
        {Jido.AgentServer.RegistrationGuard, jido: name},
        Jido.AgentServer.RegistrationGuard.registry_child_spec(
          keys: :unique,
          name: Names.registry(name)
        ),
        {RuntimeStore, name: runtime_store},
        {DynamicSupervisor,
         name: Names.agent_supervisor(name), strategy: :one_for_one, max_restarts: 1000, max_seconds: 5}
      ]

      Supervisor.init(base_children, strategy: :one_for_one)
    else
      {:error, reason} -> exit(reason)
    end
  end

  # ---------------------------------------------------------------------------
  # Stable Agent Ref API
  # ---------------------------------------------------------------------------

  @doc "Builds one stable Agent Ref in the selected instance namespace."
  @spec agent_ref(atom(), String.t(), keyword()) ::
          {:ok, Ref.t()} | {:error, Jido.Error.ValidationError.t()}
  def agent_ref(instance, id, opts \\ []) do
    with {:ok, namespace} <- require_instance_namespace(instance) do
      Ref.new_scoped(namespace, id, opts)
    end
  end

  @doc """
  Resolves the current local worker for one stable Agent Ref. Each operation
  resolves the Ref again; it does not retry or replay an accepted turn.

  Returns `{:error, :not_found}` when there is no live registration,
  `{:error, :recovering}` while AgentServer is registered but not ready, or
  `{:error, :unavailable}` when the Registry cannot be read. A worker can still
  stop after resolution. Caller timeout does not cancel an accepted turn.
  """
  @spec resolve_agent(atom(), Ref.t()) :: {:ok, pid()} | {:error, term()}
  def resolve_agent(instance, %Ref{} = ref), do: resolve_ref_target(instance, ref)

  @doc "Starts one Agent with an explicit stable Agent Ref."
  @spec start_agent_ref(atom(), Ref.t(), module() | Jido.Agent.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent_ref(instance, %Ref{} = ref, agent, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, opts} <- Ref.startup_options(ref, opts) do
      start_agent(instance, agent, opts)
    end
  end

  @doc "Activates one durable Agent with an explicit stable Agent Ref."
  @spec activate_agent(atom(), Ref.t(), module(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def activate_agent(instance, %Ref{} = ref, agent_module, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, opts} <- Ref.startup_options(ref, opts) do
      thaw(instance, agent_module, ref.id, opts)
    end
  end

  @doc "Sends one synchronous Signal through a stable Agent Ref."
  @spec call(atom(), Ref.t(), Jido.Signal.t(), timeout() | keyword()) ::
          Jido.AgentServer.signal_result()
  def call(instance, %Ref{} = ref, signal, timeout_or_opts \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.call(&1, signal, timeout_or_opts))
  end

  @doc "Sends one best-effort asynchronous Signal through a stable Agent Ref."
  @spec cast(atom(), Ref.t(), Jido.Signal.t()) :: :ok | {:error, term()}
  def cast(instance, %Ref{} = ref, signal) do
    with_ref_server(instance, ref, &AgentServer.cast(&1, signal))
  end

  @doc "Submits one AgentServer turn through a stable Agent Ref."
  @spec submit(atom(), Ref.t(), Jido.Signal.t(), keyword()) ::
          Jido.AgentServer.pending() | {:error, term()}
  def submit(instance, %Ref{} = ref, signal, opts \\ []) do
    with_ref_server(instance, ref, &AgentServer.submit(&1, signal, opts))
  end

  @doc "Collects an AgentServer pending reply in its submitting process."
  @spec await(Jido.AgentServer.pending(), timeout()) :: Jido.AgentServer.signal_result()
  defdelegate await(pending, timeout \\ 5_000), to: Jido.AgentServer

  @doc "Discards an AgentServer pending reply without cancelling its turn."
  @spec abandon(Jido.AgentServer.pending()) :: :ok | {:error, term()}
  defdelegate abandon(pending), to: Jido.AgentServer

  @doc "Stops the local Agent resolved by a stable Agent Ref."
  @spec stop_agent_ref(atom(), Ref.t(), term(), timeout()) :: :ok | {:error, term()}
  def stop_agent_ref(instance, %Ref{} = ref, reason \\ :shutdown, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.stop(&1, reason, timeout))
  end

  @doc "Persists and stops the local Agent resolved by a stable Agent Ref."
  @spec hibernate_ref(atom(), Ref.t(), keyword()) :: :ok | {:error, term()}
  def hibernate_ref(instance, %Ref{} = ref, opts \\ []) do
    with_ref_server(instance, ref, &AgentServer.hibernate(&1, opts))
  end

  @doc "Writes a durable tombstone for one inactive stable Agent Ref."
  @spec delete_agent(atom(), Ref.t(), module(), keyword()) :: :ok | {:error, term()}
  def delete_agent(instance, %Ref{} = ref, agent_module, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, opts} <- validate_ref_delete_options(opts),
         {:error, :not_found} <- resolve_ref_target(instance, ref) do
      source = Keyword.get(opts, :persistence, instance)

      persistence_opts =
        opts
        |> Keyword.delete(:persistence)
        |> Keyword.put(:instance, instance)
        |> Keyword.put(:namespace, ref.namespace)
        |> Keyword.put(:partition, ref.partition)

      Jido.Persistence.delete_agent(source, agent_module, ref.id, persistence_opts)
    else
      {:ok, _pid} -> {:error, :agent_running}
      {:error, _reason} = error -> error
    end
  end

  @doc "Cancels current pre-commit work for one stable Agent Ref."
  @spec cancel(atom(), Ref.t(), timeout()) :: :ok | {:error, term()}
  def cancel(instance, %Ref{} = ref, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.cancel(&1, timeout))
  end

  @doc "Cancels one matching Turn for a stable Agent Ref."
  @spec cancel_turn(atom(), Ref.t(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(instance, %Ref{} = ref, turn_id, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.cancel_turn(&1, turn_id, timeout))
  end

  @doc "Attaches an owner process through a stable Agent Ref."
  @spec attach(atom(), Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.attach(&1, owner_pid, timeout))
  end

  @doc "Detaches an owner process through a stable Agent Ref."
  @spec detach(atom(), Ref.t(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(instance, %Ref{} = ref, owner_pid \\ self(), timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.detach(&1, owner_pid, timeout))
  end

  @doc "Resets the idle timer through a stable Agent Ref."
  @spec touch(atom(), Ref.t()) :: :ok | {:error, term()}
  def touch(instance, %Ref{} = ref) do
    with_ref_server(instance, ref, &AgentServer.touch/1)
  end

  @doc "Returns the committed Agent through a stable Agent Ref."
  @spec agent(atom(), Ref.t(), timeout()) :: Jido.Agent.t() | {:error, term()}
  def agent(instance, %Ref{} = ref, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.agent(&1, timeout))
  end

  @doc "Returns one Plugin-owned field from the complete Agent state through a stable Ref."
  @spec plugin_state(atom(), Ref.t(), module(), timeout()) ::
          {:ok, term()} | {:error, term()}
  def plugin_state(instance, %Ref{} = ref, plugin, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.plugin_state(&1, plugin, timeout))
  end

  @doc "Returns Turn status through a stable Agent Ref."
  @spec status(atom(), Ref.t(), timeout()) :: Jido.AgentServer.Status.t() | {:error, term()}
  def status(instance, %Ref{} = ref, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.status(&1, timeout))
  end

  @doc "Returns child runtime status through a stable Agent Ref."
  @spec children(atom(), Ref.t(), timeout()) :: map() | {:error, term()}
  def children(instance, %Ref{} = ref, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.children(&1, timeout))
  end

  @doc "Waits for runtime readiness through a stable Agent Ref."
  @spec await_ready(atom(), Ref.t(), timeout()) :: :ok | {:error, term()}
  def await_ready(instance, %Ref{} = ref, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.await_ready(&1, timeout))
  end

  defp with_ref_server(instance, ref, operation) do
    with {:ok, pid} <- resolve_ref_target(instance, ref) do
      try do
        operation.(pid)
      catch
        :exit, reason ->
          if not match?({:timeout, _}, reason),
            do: {:error, :unavailable},
            else: exit(reason)
      end
    end
  end

  defp resolve_ref_target(instance, ref) do
    with {:ok, _ref} <- validate_instance_ref(instance, ref) do
      key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

      case Registry.lookup(Names.registry(instance), key) do
        [{pid, status}] -> resolve_registered_agent(pid, status)
        _other -> {:error, :not_found}
      end
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp resolve_registered_agent(pid, status) do
    case {status, :proc_lib.translate_initial_call(pid)} do
      {:ready, {AgentServer, :init, 1}} -> {:ok, pid}
      {:starting, {AgentServer, :init, 1}} -> {:error, :recovering}
      _other -> {:error, :not_found}
    end
  end

  defp validate_instance_ref(instance, ref) do
    with {:ok, namespace} <- require_instance_namespace(instance) do
      Ref.validate_namespace(ref, namespace)
    end
  end

  defp require_instance_namespace(instance) do
    case NamespaceRegistry.namespace(instance) do
      namespace when is_binary(namespace) ->
        {:ok, namespace}

      nil ->
        {:error,
         Jido.Error.validation_error("Jido instance does not have a stable namespace",
           kind: :input,
           subject: Jido.Agent.Ref,
           details: %{
             code: :jido_namespace_required,
             instance: instance
           }
         )}
    end
  end

  defp validate_ref_delete_options(opts) do
    if Keyword.keyword?(opts) and length(Keyword.keys(opts)) == length(Enum.uniq(Keyword.keys(opts))) do
      {:ok, opts}
    else
      {:error,
       Jido.Error.validation_error("Agent Ref delete options must be a unique keyword list",
         kind: :input,
         subject: Jido.Agent.Ref,
         details: %{code: :jido_instance_invalid_config, value: opts}
       )}
    end
  end

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts one Agent under the default or selected Jido instance supervisor.

  The one-argument form uses the default instance started by `Jido.start/1`:

      {:ok, _jido} = Jido.start()
      agent = MyAgent.instantiate!(id: "agent-1")
      {:ok, server} = Jido.start_agent(agent)

  Pass an instance as the first argument when the application runs more than
  one Jido supervisor:

      {:ok, server} = Jido.start_agent(MyApp.Jido, agent)

  The Agent Server links to its supervisor, not to the calling process. Caller
  exit does not stop the Agent. Use `Jido.AgentServer.start_link/1` when the
  calling process must own that link.

  Options must be a keyword list. An omitted `:id` generates a new identity;
  an explicit ID must be a nonempty string. `:state` replaces matching
  declared initial-state fields before the Agent module's optional
  `initialize/2` callback runs. An existing Agent instance keeps its ID and
  state and rejects instance overrides. A live ID is unique within its instance
  and partition. Starting a duplicate returns an error and leaves the existing
  Agent unchanged.

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
      {instance_opts, runtime_opts} = Keyword.split(opts, [:id, :state])

      with {:ok, agent} <- startup_agent(agent, instance_opts, runtime_opts) do
        runtime_opts
        |> Keyword.merge(agent: agent, jido: instance)
        |> Jido.AgentServer.start()
      end
    else
      {:error, Jido.Error.validation_error("Agent startup options must be a keyword list", kind: :config)}
    end
  end

  @doc "Stops one Agent under the default Jido instance."
  @spec stop_agent(Jido.AgentServer.server() | String.t()) ::
          :ok | {:error, :not_found | Jido.Error.ValidationError.t()}
  def stop_agent(pid_or_id), do: stop_agent(@default_instance, pid_or_id, [])

  @doc """
  Stops an Agent with options in the default instance, or stops an Agent in
  the selected instance with default options.
  """
  @spec stop_agent(
          atom() | Jido.AgentServer.server() | String.t(),
          keyword() | Jido.AgentServer.server() | String.t()
        ) ::
          :ok | {:error, :not_found | Jido.Error.ValidationError.t()}
  def stop_agent(pid_or_id, opts) when is_list(opts),
    do: stop_agent(@default_instance, pid_or_id, opts)

  def stop_agent(instance, pid_or_id) when is_atom(instance),
    do: stop_agent(instance, pid_or_id, [])

  @doc "Stops an Agent with options in the selected Jido instance."
  @spec stop_agent(atom(), Jido.AgentServer.server() | String.t(), keyword()) ::
          :ok | {:error, :not_found | Jido.Error.ValidationError.t()}
  def stop_agent(instance, pid_or_id, opts)

  def stop_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    if Keyword.keyword?(opts) do
      case whereis_agent(instance, id, opts) do
        nil -> {:error, :not_found}
        pid -> stop_agent(instance, pid, opts)
      end
    else
      invalid_compat_input(:stop_agent, %{id: id, opts: opts})
    end
  end

  def stop_agent(instance, server, opts)
      when is_atom(instance) and is_list(opts) do
    with :ok <- validate_compat_server(server),
         :ok <- validate_compat_options(:stop_agent, opts),
         {:ok, pid} <- owned_agent_server(instance, server, opts) do
      Jido.AgentServer.stop(pid)
    end
  catch
    :exit, :noproc -> {:error, :not_found}
    :exit, {:noproc, _details} -> {:error, :not_found}
    :exit, {:normal, _details} -> :ok
  end

  def stop_agent(_instance, id, opts),
    do: invalid_compat_input(:stop_agent, %{id: id, opts: opts})

  @doc "Looks up one Agent by id under the default Jido instance."
  @spec whereis_agent(String.t()) :: pid() | nil | {:error, Jido.Error.ValidationError.t()}
  def whereis_agent(id), do: whereis_agent(@default_instance, id, [])

  @doc """
  Looks up an Agent with options in the default instance, or looks up an Agent
  in the selected instance with default options.
  """
  @spec whereis_agent(atom() | String.t(), keyword() | String.t()) ::
          pid() | nil | {:error, Jido.Error.ValidationError.t()}
  def whereis_agent(id, opts) when is_binary(id) and is_list(opts),
    do: whereis_agent(@default_instance, id, opts)

  def whereis_agent(instance, id) when is_atom(instance),
    do: whereis_agent(instance, id, [])

  def whereis_agent(id, opts), do: invalid_compat_input(:whereis_agent, %{id: id, opts: opts})

  @doc "Looks up an Agent with options in the selected Jido instance."
  @spec whereis_agent(atom(), String.t(), keyword()) ::
          pid() | nil | {:error, Jido.Error.ValidationError.t()}
  def whereis_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    if Keyword.keyword?(opts) do
      Jido.AgentServer.whereis(
        instance,
        id,
        partition: Keyword.get(opts, :partition)
      )
    else
      invalid_compat_input(:whereis_agent, %{id: id, opts: opts})
    end
  end

  def whereis_agent(_instance, id, opts),
    do: invalid_compat_input(:whereis_agent, %{id: id, opts: opts})

  @doc "Lists all Agents in the default Jido instance."
  @spec list_agents() :: [{String.t(), pid()}] | {:error, Jido.Error.ValidationError.t()}
  def list_agents, do: list_agents(@default_instance, [])

  @doc "Lists Agents with default-instance options, or lists a selected instance."
  @spec list_agents(keyword() | atom()) ::
          [{String.t(), pid()}] | {:error, Jido.Error.ValidationError.t()}
  def list_agents(opts) when is_list(opts), do: list_agents(@default_instance, opts)
  def list_agents(instance) when is_atom(instance), do: list_agents(instance, [])

  @doc "Lists Agents with options in the selected Jido instance."
  @spec list_agents(atom(), keyword()) ::
          [{String.t(), pid()}] | {:error, Jido.Error.ValidationError.t()}
  def list_agents(instance, opts)
      when is_atom(instance) and is_list(opts) do
    if Keyword.keyword?(opts) do
      partition = Keyword.get(opts, :partition)

      instance
      |> Names.registry()
      |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
      |> Enum.flat_map(fn
        {{:agent, key}, pid, :ready} ->
          case Names.unwrap_partition_key(key) do
            {^partition, id} when is_binary(id) -> [{id, pid}]
            _other -> []
          end

        _entry ->
          []
      end)
      |> Enum.filter(fn {_id, pid} -> Process.alive?(pid) end)
    else
      invalid_compat_input(:list_agents, %{opts: opts})
    end
  end

  def list_agents(_instance, opts), do: invalid_compat_input(:list_agents, %{opts: opts})

  @doc "Returns the count of live Agents in the default Jido instance."
  @spec agent_count() :: non_neg_integer() | {:error, Jido.Error.ValidationError.t()}
  def agent_count, do: agent_count(@default_instance, [])

  @doc "Counts Agents with default-instance options, or counts a selected instance."
  @spec agent_count(keyword() | atom()) ::
          non_neg_integer() | {:error, Jido.Error.ValidationError.t()}
  def agent_count(opts) when is_list(opts), do: agent_count(@default_instance, opts)
  def agent_count(instance) when is_atom(instance), do: agent_count(instance, [])

  @doc "Counts live Agents with options in the selected Jido instance."
  @spec agent_count(atom(), keyword()) ::
          non_neg_integer() | {:error, Jido.Error.ValidationError.t()}
  def agent_count(instance, opts) do
    case list_agents(instance, opts) do
      agents when is_list(agents) -> length(agents)
      {:error, _reason} = error -> error
    end
  end

  defp validate_compat_options(operation, opts) do
    if Keyword.keyword?(opts),
      do: :ok,
      else: invalid_compat_input(operation, %{opts: opts})
  end

  defp validate_compat_server(server)
       when is_pid(server) or is_atom(server) or is_tuple(server),
       do: :ok

  defp validate_compat_server(server),
    do: invalid_compat_input(:stop_agent, %{server: server})

  defp invalid_compat_input(operation, details) do
    {:error,
     Jido.Error.validation_error("Jido compatibility input is invalid",
       kind: :input,
       subject: __MODULE__,
       details: Map.put(details, :operation, operation)
     )}
  end

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
    opts =
      opts
      |> Keyword.put(:id, agent_id)
      |> Keyword.put_new(:persistence, :inherit)
      |> Keyword.put(:persistence_mode, :restore)

    start_agent(instance, agent_module, opts)
  end

  defp startup_agent(%Jido.Agent{id: id} = agent, opts, _runtime_opts) when is_binary(id) do
    if Keyword.delete(opts, :id) == [] and Keyword.get(opts, :id, id) == id,
      do: {:ok, agent},
      else: invalid_compat_input(:start_agent, %{opts: opts})
  end

  defp startup_agent(source, opts, runtime_opts) do
    if runtime_opts[:persistence_mode] == :restore do
      with {:ok, definition} <- Jido.Agent.Validation.resolve(source),
           {:ok, opts} <- Jido.Agent.Schema.options(opts, [:id]),
           :ok <- Jido.Agent.Schema.nonempty(opts[:id]),
           do: {:ok, %{definition | id: opts.id}}
    else
      Jido.Agent.instantiate(source, opts)
    end
  end

  defp owned_agent_server(instance, server, opts) do
    with true <- not is_nil(instance),
         true <- Keyword.keyword?(opts),
         pid when is_pid(pid) <- safe_whereis(server),
         %{jido: ^instance, agent_id: agent_id, partition: partition} <-
           Jido.AgentServer.status(pid),
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
    not Keyword.has_key?(opts, :partition) or Keyword.get(opts, :partition) === partition
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
