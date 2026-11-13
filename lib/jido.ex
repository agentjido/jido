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

      {:ok, pid} = Jido.start_agent(MyApp.Jido, MyAgent, id: "agent-1")
      pid = Jido.whereis_agent(MyApp.Jido, "agent-1")
      agents = Jido.list_agents(MyApp.Jido)
      :ok = Jido.stop_agent(MyApp.Jido, "agent-1")

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

  Use `Jido.AgentServer.snapshot/2` for the committed Agent. Use
  `Jido.AgentServer.status/2` for the revision and current runtime work.

  `Jido.Telemetry` is the system-wide observation contract. Its semantic event
  catalog supplies Telemetry events, standard metrics, bounded logs, and
  optional OpenTelemetry spans. `Jido.Telemetry.set_debug/2` changes semantic
  log detail for one instance.

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
    - `:persistence` - Optional persistence profile. A Store declaration uses
      the compact Term codec. A profile can select the opt-in JSON codec.
      The default is no durable persistence.

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
      @spec __jido_persistence__() :: Jido.Persistence.Config.t() | nil
      def __jido_persistence__, do: Jido.Persistence.Config.normalize(unquote(persistence))

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
    end
  end

  @type partition :: term()

  # Default instance name for scripts/Livebook
  @default_instance Jido.Default

  # ---------------------------------------------------------------------------
  # Generated instance configuration
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Default instance
  # ---------------------------------------------------------------------------

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
      {:ok, pid} = Jido.start_agent(Jido.Default, MyAgent)

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
    - `:persistence` - Optional instance persistence profile. All Agents in the
      instance use this one Store and codec. Persistent instances require a
      stable namespace.
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

      result = await_wake_readiness(result, Keyword.fetch!(opts, :name))

      if not match?({:ok, _pid}, result), do: NamespaceRegistry.release(claim)
      result
    end
  end

  defp await_wake_readiness({:ok, pid} = started, name) do
    case Jido.Instance.Wake.await_ready(name) do
      :ok ->
        started

      {:error, _reason} = error ->
        Supervisor.stop(pid)
        error
    end
  end

  defp await_wake_readiness(result, _name), do: result

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
        Names.wake(name),
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
           NamespaceRegistry.bind(claim, Keyword.get(opts, :namespace), name, self()),
         :ok <- RuntimeStore.ensure_table(runtime_store),
         :ok <-
           Jido.Persistence.NamespaceManifest.open(
             Keyword.get(opts, :persistence),
             Keyword.get(opts, :namespace)
           ) do
      Jido.Telemetry.configure_debug(name, opts[:debug])

      idle_residency_timeout =
        opts
        |> Keyword.fetch!(:activation)
        |> Keyword.fetch!(:idle_residency_timeout)

      agent_server_defaults =
        opts
        |> Keyword.get(:agent_server, [])
        |> Keyword.put(:idle_timeout, idle_residency_timeout)
        |> Keyword.put(:idle_policy, if(opts[:persistence], do: :hibernate, else: :stop))

      :ok =
        RuntimeStore.put_instance_config(
          runtime_store,
          Keyword.get(opts, :persistence),
          agent_server_defaults
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
        {Jido.Instance.Wake, instance: name, name: Names.wake(name)},
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
  def resolve_agent(instance, %Ref{} = ref) do
    with :ok <- ensure_reconciled(instance, ref), do: resolve_ref_target(instance, ref)
  end

  @doc "Creates one durable Agent with an explicit stable Agent Ref."
  @spec create_agent(atom(), Ref.t(), module() | Jido.Agent.t(), keyword()) ::
          {:ok, Ref.t()} | {:error, term()}
  def create_agent(instance, %Ref{} = ref, agent, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, opts} <- Ref.operation_options(ref, opts, "Agent Ref create options"),
         :ok <- validate_create_agent_options(opts),
         {instance_opts, _runtime_opts} = Keyword.split(opts, [:id, :state]),
         {:ok, agent} <- startup_agent(agent, instance_opts, []),
         {:ok, _agent, 0, 0, nil} <-
           Jido.Persistence.open_agent(instance, agent, :create,
             instance: instance,
             namespace: ref.namespace,
             partition: ref.partition,
             reason: :create
           ) do
      {:ok, ref}
    end
  end

  @doc "Activates one existing durable Agent from its stable Agent Ref."
  @spec activate_agent(atom(), Ref.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def activate_agent(instance, %Ref{} = ref, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, opts} <- Ref.operation_options(ref, opts, "Agent Ref activation options"),
         :ok <- validate_activate_agent_options(opts),
         :ok <- ensure_reconciled(instance, ref) do
      case resolve_ref_target(instance, ref) do
        {:ok, pid} ->
          {:ok, pid}

        {:error, :not_found} ->
          restore_activation(instance, ref, opts)

        {:error, :recovering} ->
          await_ref_activation(instance, ref)

        {:error, :passivating} ->
          await_ref_passivation(instance, ref)

        {:error, _reason} = error ->
          error
      end
    end
  end

  @doc "Replaces one faulted activation from its authoritative durable record."
  @spec reconcile_agent(atom(), Ref.t(), keyword()) ::
          DynamicSupervisor.on_start_child() | {:error, term()}
  def reconcile_agent(instance, %Ref{} = ref, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         :ok <- validate_reconcile_options(opts),
         {:ok, reason} <- reconciliation_reason(instance, ref),
         :ok <- terminate_registered_activation(instance, ref),
         {:ok, _agent, _persistence_revision, _agent_revision, _turn} <-
           Jido.Persistence.load_agent_ref(instance, ref, instance: instance),
         :ok <- RuntimeStore.delete(instance, :agent_reconciliation, ref) do
      case restore_activation(instance, ref, []) do
        {:ok, _pid} = ok ->
          ok

        {:error, activation_reason} = error ->
          _ = RuntimeStore.put(instance, :agent_reconciliation, ref, {reason, activation_reason})
          error
      end
    else
      :error -> {:error, :reconciliation_not_required}
      {:error, _reason} = error -> error
    end
  end

  @doc "Upgrades one inactive durable Agent and replaces its active activation."
  @spec upgrade_agent(atom(), Ref.t(), term(), keyword()) :: {:ok, Ref.t()} | {:error, term()}
  def upgrade_agent(instance, %Ref{} = ref, action, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         :ok <- validate_upgrade_options(opts),
         :ok <- ensure_reconciled(instance, ref),
         {:ok, agent, reactivate?} <- prepare_definition_upgrade(instance, ref),
         {:ok, _upgraded, _persistence_revision} <-
           Jido.Persistence.upgrade_agent(instance, agent.module, ref.id, action,
             instance: instance,
             partition: ref.partition,
             context: Keyword.get(opts, :context, %{})
           ),
         :ok <- restore_after_upgrade(instance, ref, reactivate?) do
      {:ok, ref}
    end
  end

  defp restore_activation(instance, ref, opts) do
    with {:ok, agent, _revision, _agent_revision, _turn} <-
           Jido.Persistence.load_agent_ref(instance, ref, instance: instance) do
      opts =
        opts
        |> Keyword.put(:id, ref.id)
        |> Keyword.put(:persistence, :inherit)
        |> Keyword.put(:persistence_mode, :restore)

      case start_agent(instance, agent, opts) do
        {:error, {:already_started, _root}} -> await_ref_activation(instance, ref)
        {:ok, pid} when is_pid(pid) -> await_activated(pid)
        result -> result
      end
    end
  end

  defp await_activated(pid) do
    case AgentServer.await_ready(pid, 5_000) do
      :ok -> {:ok, pid}
      {:error, _reason} = error -> error
    end
  end

  @doc "Sends one synchronous Signal through a stable Agent Ref."
  @spec call(atom(), Ref.t(), Jido.Signal.t(), timeout() | keyword()) ::
          {:ok, Jido.AgentServer.TurnResult.t()} | {:error, term()}
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
          Jido.AgentServer.Pending.t() | {:error, term()}
  def submit(instance, %Ref{} = ref, signal, opts \\ []) do
    with_ref_server(instance, ref, &AgentServer.submit(&1, signal, opts))
  end

  @doc "Writes a durable tombstone for one inactive stable Agent Ref."
  @spec delete_agent(atom(), Ref.t(), keyword()) :: :ok | {:error, term()}
  def delete_agent(instance, %Ref{} = ref, opts \\ []) do
    with {:ok, ref} <- validate_instance_ref(instance, ref),
         {:ok, _opts} <- validate_ref_delete_options(opts),
         {:error, :not_found} <- resolve_ref_target(instance, ref) do
      Jido.Persistence.delete_agent_ref(instance, ref, instance: instance)
    else
      {:ok, _pid} -> {:error, :agent_running}
      {:error, state} when state in [:recovering, :passivating] -> {:error, :agent_running}
      {:error, _reason} = error -> error
    end
  end

  @doc "Cancels one matching Turn for a stable Agent Ref."
  @spec cancel_turn(atom(), Ref.t(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(instance, %Ref{} = ref, turn_id, timeout \\ 5_000) do
    with_ref_server(instance, ref, &AgentServer.cancel_turn(&1, turn_id, timeout))
  end

  @doc "Returns Turn status through a stable Agent Ref."
  @spec status(atom(), Ref.t(), timeout()) :: Jido.AgentServer.Status.t() | {:error, term()}
  def status(instance, %Ref{} = ref, timeout \\ 5_000) do
    with {:ok, ref} <- validate_instance_ref(instance, ref) do
      case resolve_ref_target(instance, ref) do
        {:ok, pid} ->
          AgentServer.status(pid, timeout)

        {:error, state} when state in [:recovering, :passivating] ->
          status_for_registered(instance, ref, timeout)

        {:error, :reconciliation_required} ->
          status_for_registered(instance, ref, timeout)

        {:error, :not_found} ->
          passivated_status(instance, ref)

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp status_for_registered(instance, ref, timeout) do
    key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

    case Registry.lookup(Names.registry(instance), key) do
      [{root, {:activation, _activation_id}}] ->
        case Jido.AgentServer.Supervisor.live_worker(root) do
          pid when is_pid(pid) ->
            AgentServer.status(pid, timeout)

          nil ->
            if Process.alive?(root),
              do: {:error, :recovering},
              else: passivated_status(instance, ref)
        end

      _ ->
        passivated_status(instance, ref)
    end
  end

  defp passivated_status(instance, ref) do
    case Jido.Persistence.load_agent_ref(instance, ref, instance: instance) do
      {:ok, _agent, persistence_revision, agent_revision, turn} ->
        Jido.AgentServer.Status.passivated(
          ref,
          agent_revision,
          persistence_revision,
          turn
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp with_ref_server(instance, ref, operation) do
    with {:ok, pid} <- resolve_or_activate(instance, ref) do
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

  defp resolve_or_activate(instance, ref) do
    with :ok <- ensure_reconciled(instance, ref) do
      case resolve_ref_target(instance, ref) do
        {:ok, pid} -> {:ok, pid}
        {:error, :not_found} -> activate_agent(instance, ref)
        {:error, :recovering} -> await_ref_activation(instance, ref)
        {:error, :passivating} -> await_ref_passivation(instance, ref)
        {:error, _reason} = error -> error
      end
    end
  end

  defp await_ref_activation(instance, ref),
    do: await_ref_activation(instance, ref, System.monotonic_time(:millisecond) + 5_000)

  defp await_ref_activation(instance, ref, deadline) do
    key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

    case Registry.lookup(Names.registry(instance), key) do
      [{root, {:activation, _activation_id}}] ->
        case Jido.AgentServer.Supervisor.live_worker(root) do
          pid when is_pid(pid) ->
            case AgentServer.await_ready(pid, 5_000) do
              :ok -> {:ok, pid}
              {:error, _reason} = error -> error
            end

          nil ->
            if System.monotonic_time(:millisecond) < deadline do
              Process.sleep(5)
              await_ref_activation(instance, ref, deadline)
            else
              {:error, :activation_timeout}
            end
        end

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          resolve_or_activate(instance, ref)
        else
          {:error, :activation_timeout}
        end
    end
  end

  defp await_ref_passivation(instance, ref) do
    key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

    case Registry.lookup(Names.registry(instance), key) do
      [{root, {:activation, _activation_id}}] ->
        monitor = Process.monitor(root)

        receive do
          {:DOWN, ^monitor, :process, ^root, _reason} -> activate_agent(instance, ref)
        after
          5_000 ->
            Process.demonitor(monitor, [:flush])
            {:error, :activation_timeout}
        end

      _ ->
        resolve_or_activate(instance, ref)
    end
  end

  defp resolve_ref_target(instance, ref) do
    with {:ok, _ref} <- validate_instance_ref(instance, ref) do
      key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

      case Registry.lookup(Names.registry(instance), key) do
        [{root, {:activation, _activation_id}}] -> resolve_registered_agent(root)
        _other -> {:error, :not_found}
      end
    end
  rescue
    ArgumentError -> {:error, :unavailable}
  end

  defp resolve_registered_agent(root) do
    case Jido.AgentServer.Supervisor.live_worker(root) do
      pid when is_pid(pid) ->
        case AgentServer.status(pid, 100) do
          %{work_state: :faulted} -> {:error, :reconciliation_required}
          %{residency: :passivating} -> {:error, :passivating}
          %{ready?: true} -> {:ok, pid}
          %{} -> {:error, :recovering}
          {:error, _reason} -> {:error, :recovering}
        end

      nil ->
        {:error, :recovering}
    end
  catch
    :exit, _reason -> {:error, :recovering}
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

  defp validate_create_agent_options(opts),
    do: validate_ref_operation_options(:create_agent, opts, [:id, :partition, :state])

  defp validate_activate_agent_options(opts),
    do: validate_ref_operation_options(:activate_agent, opts, [:id, :partition])

  defp validate_reconcile_options(opts),
    do: validate_ref_operation_options(:reconcile_agent, opts, [])

  defp validate_upgrade_options(opts),
    do: validate_ref_operation_options(:upgrade_agent, opts, [:context])

  defp prepare_definition_upgrade(instance, ref) do
    case resolve_ref_target(instance, ref) do
      {:ok, pid} ->
        case AgentServer.status(pid) do
          %{work_state: :idle, queue_depth: 0, effects: :none} ->
            with {:ok, snapshot} <- AgentServer.stop(pid, :definition_upgrade, 5_000),
                 do: {:ok, snapshot.agent, true}

          %{} ->
            {:error, :agent_busy}

          {:error, _reason} = error ->
            error
        end

      {:error, :not_found} ->
        with {:ok, agent, _persistence_revision, _agent_revision, _turn} <-
               Jido.Persistence.load_agent_ref(instance, ref, instance: instance),
             do: {:ok, agent, false}

      {:error, state} when state in [:recovering, :passivating] ->
        {:error, :agent_busy}

      {:error, _reason} = error ->
        error
    end
  end

  defp restore_after_upgrade(_instance, _ref, false), do: :ok

  defp restore_after_upgrade(instance, ref, true) do
    case activate_agent(instance, ref) do
      {:ok, _pid} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp ensure_reconciled(instance, ref) do
    case reconciliation_reason(instance, ref) do
      {:ok, _reason} -> {:error, :reconciliation_required}
      :error -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp reconciliation_reason(instance, ref),
    do: RuntimeStore.fetch(instance, :agent_reconciliation, ref)

  defp terminate_registered_activation(instance, ref) do
    key = AgentServer.RegistrationGuard.registry_key(ref.id, ref.partition)

    case Registry.lookup(Names.registry(instance), key) do
      [{root, {:activation, _activation_id}}] ->
        case DynamicSupervisor.terminate_child(Names.agent_supervisor(instance), root) do
          :ok -> :ok
          {:error, :not_found} -> :ok
        end

      _other ->
        :ok
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp validate_ref_operation_options(operation, opts, allowed) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      keys ->
        {:error,
         Jido.Error.validation_error("Agent Ref operation options contain unknown keys",
           kind: :input,
           subject: Jido.Agent.Ref,
           details: %{
             code: :jido_instance_invalid_config,
             operation: operation,
             keys: Enum.uniq(keys)
           }
         )}
    end
  end

  # ---------------------------------------------------------------------------
  # Agent Lifecycle
  # ---------------------------------------------------------------------------

  @doc """
  Starts one Agent under the selected Jido instance supervisor.

  Pass `Jido.Default` after `Jido.start/1` in a script or Livebook:

      {:ok, _jido} = Jido.start()
      agent = MyAgent.instantiate!(id: "agent-1")
      {:ok, server} = Jido.start_agent(Jido.Default, agent)

  Pass an application instance module in a supervised application:

      {:ok, server} = Jido.start_agent(MyApp.Jido, agent)

  The Agent Server links to its supervisor, not to the calling process. Caller
  exit does not stop the Agent.

  Options must be a keyword list. An omitted `:id` generates a new identity;
  an explicit ID must be a nonempty string. `:state` replaces matching
  declared initial-state fields before the Agent module's optional
  `initialize/2` callback runs. An existing Agent instance keeps its ID and
  state and rejects instance overrides. A live ID is unique within its instance
  and partition. Starting a duplicate returns an error and leaves the existing
  Agent unchanged.

  An instance with persistence uses its one configured Store and codec for all
  Agents. Per-Agent Store overrides are not supported.

  This is the standard example startup API. Domain command functions can stay
  in the Agent module; they do not need a matching startup wrapper.
  """
  @spec start_agent(atom(), module() | Jido.Agent.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def start_agent(instance, agent, opts \\ []) when is_atom(instance) do
    if is_list(opts) and Keyword.keyword?(opts) do
      {instance_opts, runtime_opts} = Keyword.split(opts, [:id, :state])

      with :ok <- validate_agent_persistence_override(runtime_opts),
           {:ok, agent} <- startup_agent(agent, instance_opts, runtime_opts) do
        runtime_opts
        |> inherit_instance_persistence(instance)
        |> Keyword.merge(agent: agent, jido: instance)
        |> Jido.AgentServer.Worker.start()
      end
    else
      {:error, Jido.Error.validation_error("Agent startup options must be a keyword list", kind: :config)}
    end
  end

  defp validate_agent_persistence_override(opts) do
    case Keyword.fetch(opts, :persistence) do
      :error ->
        :ok

      {:ok, value} when value in [:inherit, nil, false] ->
        :ok

      {:ok, value} ->
        {:error,
         Jido.Error.validation_error("Per-Agent persistence is not supported",
           kind: :config,
           details: %{persistence: value}
         )}
    end
  end

  defp inherit_instance_persistence(opts, instance) do
    case Jido.Instance.RuntimeStore.instance_persistence(instance) do
      %Jido.Persistence.Config{} -> Keyword.put(opts, :persistence, :inherit)
      nil -> Keyword.put(opts, :persistence, false)
    end
  end

  @doc "Stops an Agent with options in the selected Jido instance."
  @spec stop_agent(atom(), Jido.AgentServer.server() | String.t(), keyword()) ::
          :ok | {:error, :not_found | Jido.Error.ValidationError.t()}
  def stop_agent(instance, pid_or_id, opts \\ [])

  def stop_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    if Keyword.keyword?(opts) do
      case whereis_agent(instance, id, opts) do
        nil -> {:error, :not_found}
        pid -> stop_agent(instance, pid, opts)
      end
    else
      invalid_runtime_input(:stop_agent, %{id: id, opts: opts})
    end
  end

  def stop_agent(instance, server, opts)
      when is_atom(instance) and is_list(opts) do
    with :ok <- validate_server(server),
         :ok <- validate_runtime_options(:stop_agent, opts),
         {:ok, pid} <- owned_agent_server(instance, server, opts) do
      case Jido.AgentServer.stop(pid) do
        {:ok, _snapshot} -> :ok
        {:error, _reason} = error -> error
      end
    end
  catch
    :exit, :noproc -> {:error, :not_found}
    :exit, {:noproc, _details} -> {:error, :not_found}
    :exit, {:normal, _details} -> :ok
  end

  def stop_agent(_instance, id, opts),
    do: invalid_runtime_input(:stop_agent, %{id: id, opts: opts})

  @doc "Looks up an Agent with options in the selected Jido instance."
  @spec whereis_agent(atom(), String.t(), keyword()) ::
          pid() | nil | {:error, Jido.Error.ValidationError.t()}
  def whereis_agent(instance, id, opts \\ [])

  def whereis_agent(instance, id, opts)
      when is_atom(instance) and is_binary(id) and is_list(opts) do
    if Keyword.keyword?(opts) do
      Jido.AgentServer.Worker.whereis(
        instance,
        id,
        partition: Keyword.get(opts, :partition)
      )
    else
      invalid_runtime_input(:whereis_agent, %{id: id, opts: opts})
    end
  end

  def whereis_agent(_instance, id, opts),
    do: invalid_runtime_input(:whereis_agent, %{id: id, opts: opts})

  @doc "Lists Agents with options in the selected Jido instance."
  @spec list_agents(atom(), keyword()) ::
          [{String.t(), pid()}] | {:error, Jido.Error.ValidationError.t()}
  def list_agents(instance, opts \\ [])

  def list_agents(instance, opts)
      when is_atom(instance) and is_list(opts) do
    if Keyword.keyword?(opts) do
      partition = Keyword.get(opts, :partition)

      instance
      |> Names.registry()
      |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}])
      |> Enum.flat_map(fn
        {{:agent, key}, root, {:activation, _activation_id}} ->
          case Names.unwrap_partition_key(key) do
            {^partition, id} when is_binary(id) ->
              case Jido.AgentServer.Supervisor.live_worker(root) do
                pid when is_pid(pid) -> [{id, pid}]
                nil -> []
              end

            _other ->
              []
          end

        _entry ->
          []
      end)
      |> Enum.filter(fn {_id, pid} -> Process.alive?(pid) end)
    else
      invalid_runtime_input(:list_agents, %{opts: opts})
    end
  rescue
    # Registry.select/2 raises when the instance is not running.
    ArgumentError -> invalid_runtime_input(:list_agents, %{instance: instance})
  end

  def list_agents(_instance, opts), do: invalid_runtime_input(:list_agents, %{opts: opts})

  @doc "Counts resident Agent activations in the selected Jido instance."
  @spec resident_agent_count(atom(), keyword()) ::
          non_neg_integer() | {:error, Jido.Error.ValidationError.t()}
  def resident_agent_count(instance, opts \\ []) do
    case list_agents(instance, opts) do
      agents when is_list(agents) -> length(agents)
      {:error, _reason} = error -> error
    end
  end

  defp validate_runtime_options(operation, opts) do
    if Keyword.keyword?(opts),
      do: :ok,
      else: invalid_runtime_input(operation, %{opts: opts})
  end

  defp validate_server(server)
       when is_pid(server) or is_atom(server) or is_tuple(server),
       do: :ok

  defp validate_server(server),
    do: invalid_runtime_input(:stop_agent, %{server: server})

  defp invalid_runtime_input(operation, details) do
    {:error,
     Jido.Error.validation_error("Jido runtime input is invalid",
       kind: :input,
       subject: __MODULE__,
       details: Map.put(details, :operation, operation)
     )}
  end

  @doc "Thaws an Agent with options in the selected Jido instance."
  @spec thaw(atom(), module(), String.t(), keyword()) ::
          DynamicSupervisor.on_start_child()
  def thaw(instance, agent_module, agent_id, opts \\ [])
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
      else: invalid_runtime_input(:start_agent, %{opts: opts})
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
         %{agent_ref: %{id: agent_id, partition: partition}} <-
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
