defmodule Jido.AgentServer do
  @moduledoc """
  The responsive OTP owner for one live `Jido.Agent`.

  This Server uses four active `:gen_statem` states: `:idle`, `:admitting`,
  `:running`, and `:directing`. One Signal selects one Action or Flow. Live
  Plugin admission, `Jido.Exec`, and outbound Plugin work run asynchronously.
  The Server commits only the terminal complete state result. It then
  notifies selected Plugin `after_commit/3` hooks in declaration order, then
  interprets returned Directives in list order before it accepts the next Signal.

  The Agent state commit is atomic. Turn execution is not a transaction across
  external systems: an Action or Flow can complete I/O before returning an
  error. That failure preserves committed Agent state but does not undo the
  I/O. Applications own external idempotency and recovery.

  Signals that arrive during a turn are postponed by OTP. OTP retains each full
  postponed event. The Server keeps bounded admission tokens so it can reject
  excess work. This limit does not bound messages that have not yet reached the
  state-machine callback.

  The Server assigns one stable UUID7 to each admitted Turn. It keeps a private
  `ActiveTurn` until execution, commit notifications, and all Directives stop.
  It then creates one runtime `Jido.Agent.Turn.Outcome`. A custom two-argument error
  policy receives the original error and this Outcome. When the Agent debug
  buffer is on, the terminal event contains a bounded outcome summary. It does
  not contain the complete Outcome, Agent state, or full Signals.

  Before a commit, the Server writes either an instance-owned runtime checkpoint
  or a configured durable persistence record. This prevents a transient Agent
  restart from using its old initialization value. Persistence records survive
  a complete Jido instance restart. A stopping policy uses a clean shutdown and
  does not restart the Agent from old state.

  `state_version` is the commit revision. Each successful Turn advances it once,
  even when the complete state equals the prior state. The checkpoint stores
  that revision before the caller receives success. To reject a duplicate
  without a commit, an Action can return `{:error, reason}`. No separate no-op
  result is required. A failure after commit does not undo the revision.

  `turn_timeout` starts when active pre-commit work starts and stops when commit
  starts. It covers Plugin admission and candidate evaluation. Timeout cancels
  owned work, keeps the committed snapshot, and rejects later task messages.
  Caller wait, Plugin readiness, persistence operations, and post-commit
  Directive work use separate boundaries.

  Exec roots, Action tasks, Flow tasks, commit notifications, and asynchronous
  Directives run under the Jido instance Task Supervisor. The Server also links each Exec root to
  itself. Initial Plugin readiness and error Signal delivery are also linked
  to the Server. Owned work cannot outlive its Agent owner.

  Use `agent/2` for the committed Agent, `snapshot/2` for the Agent and commit
  revision, `status/2` for current runtime work, and `children/2` for live
  ownership. Use `set_debug/3` and `recent_events/3` for a short diagnostic
  history for one Agent. Use `Jido.Telemetry` for system-wide runtime
  observation. See
  [Runtime State and Debugging](runtime-state-and-debugging.html) for an
  executable inspection example.
  """

  @behaviour :gen_statem

  alias Jido.AgentServer.Admission
  alias Jido.AgentServer.Cancellation
  alias Jido.AgentServer.ChildOperations
  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.PostCommit
  alias Jido.AgentServer.ServerLifecycle
  alias Jido.AgentServer.Turn

  alias Jido.Agent
  alias Jido.Agent.Directive

  alias Jido.AgentServer.{
    ActiveTurn,
    AdmissionDeadline,
    ChildLifecycle,
    ExecutionAdapter,
    FailurePolicy,
    TaskSupport,
    Inspection,
    Options,
    ParentRef,
    PluginLifecycle,
    RegistrationGuard,
    Shutdown,
    State,
    Storage,
    Upgrade
  }

  alias Jido.Error
  alias Jido.Signal

  @type server :: pid() | atom() | {:global, term()} | {:via, module(), term()}
  @type signal_result :: {:ok, Agent.t()} | {:error, term()}
  @type upgrade_operation :: (-> :ok | {:error, term()})
  @type state_migration :: (Agent.t() -> {:ok, map()} | {:error, term()})

  @doc """
  Starts one Agent Server linked to the calling process.

  Use `Jido.start_agent/3` for instance-supervised ownership instead.
  """
  @spec start_link(keyword()) :: :gen_statem.start_ret()
  def start_link(opts) when is_list(opts), do: start_link(opts, nil)

  @doc false
  def start_link(opts, startup_reply) when is_list(opts) do
    with {:ok, options} <- Options.new(opts) do
      case server_name(options) do
        nil -> :gen_statem.start_link(__MODULE__, {options, startup_reply}, [])
        name -> :gen_statem.start_link(name, __MODULE__, {options, startup_reply}, [])
      end
    end
  end

  @doc """
  Starts one Agent Server under its Jido instance supervisor.

  The Server links to that supervisor. It does not link to the original caller.
  """
  @spec start(keyword()) :: DynamicSupervisor.on_start_child()
  def start(opts) when is_list(opts) do
    case Keyword.get(opts, :jido) do
      jido when is_atom(jido) and not is_nil(jido) ->
        # Register the reply address before the child can finish bootstrap.
        # An alias also drops a late reply when the caller stops waiting.
        reply = :erlang.alias()
        spec = %{child_spec(opts) | start: {__MODULE__, :start_link, [opts, reply]}}

        try do
          case DynamicSupervisor.start_child(Jido.agent_supervisor_name(jido), spec) do
            {:ok, pid} -> startup_result(pid, reply)
            {:ok, pid, _info} -> startup_result(pid, reply)
            result -> result
          end
        after
          :erlang.unalias(reply)
        end

      _value ->
        {:error, :jido_instance_required}
    end
  end

  @doc "Returns a child specification for one Agent Server."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = Keyword.get(opts, :id, make_ref())
    default_restart = if Keyword.get(opts, :jido), do: :transient, else: :temporary
    restart = Keyword.get(opts, :restart, default_restart)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: restart,
      shutdown: 5_000
    }
  end

  @call_schema Zoi.object(
                 %{
                   timeout:
                     Zoi.union([Zoi.integer() |> Zoi.min(0), Zoi.literal(:infinity)])
                     |> Zoi.default(5_000),
                   context: Zoi.any() |> Zoi.default(%{})
                 },
                 unrecognized_keys: :error
               )

  @type call_option :: {:timeout, timeout()} | {:context, map() | keyword() | nil}

  @doc """
  Sends one Signal and waits for its commit or failure.

  The third argument accepts a timeout or a keyword list with `:timeout` and
  `:context`. The default timeout is 5,000 milliseconds. Context accepts a map,
  keyword list, or `nil`, as in `Jido.Agent.cmd/3`.

  Caller context passes through Plugin admission to execution.
  It belongs to this Turn, including its post-commit Plugin work. Jido does not
  add it to Signal data, the complete Agent state, persistence, or emitted Signals.
  Application code must select any values it wants to store or emit.

  A durable revision conflict returns `{:error, {:persistence_failed, :conflict}}`
  before live state changes or Directives run. Every required persistence write
  error stops this activation before it can accept more work. The Server does
  not reload or retry the command automatically; external Action work may
  already have completed. For an indeterminate result, the write can have
  completed even if its reply was lost. A new activation must restore the
  authoritative stored state before it can continue.

  `:agent_id`, `:agent_state`, `:signal`, and `:plugin_inputs` are reserved
  execution keys. The live Server sets `:jido` and `:partition` from its own
  state and overrides caller values for those two keys. Direct `Jido.Agent.cmd/3`
  has no Server state, so those keys stay caller-owned there. Caller timeout stops
  waiting; it does not cancel execution that has already started.
  Admission time starts at the caller. Remote admission queries the caller's
  monotonic clock with a one-second bound and counts the query duration.
  An unavailable clock rejects admission. No wall-clock agreement is required.
  Infinite admission budgets do not query a remote clock.

      Server.call(server, signal, context: %{client: client}, timeout: 10_000)
  """
  @spec call(server(), Signal.t(), timeout() | [call_option()]) :: signal_result()
  def call(server, signal, timeout_or_opts \\ 5_000)

  def call(server, %Signal{} = signal, opts) when is_list(opts) do
    with {:ok, opts} <- Options.validate_keyword(opts, :call),
         {:ok, options} <- parse_call_options(opts),
         {:ok, context} <- Jido.Agent.Command.normalize_context(options.context) do
      call_with_context(server, signal, options.timeout, context)
    end
  end

  def call(server, %Signal{} = signal, timeout) do
    call_with_context(server, signal, timeout, %{})
  end

  defp parse_call_options(opts) do
    case Zoi.parse(@call_schema, Map.new(opts)) do
      {:ok, options} ->
        {:ok, options}

      {:error, issues} ->
        {:error,
         Error.validation_error("Invalid Agent Server call options", details: %{issues: issues})}
    end
  end

  defp call_with_context(server, signal, timeout, context) do
    :gen_statem.call(
      server,
      {:signal, make_ref(), signal, AdmissionDeadline.new(timeout), context},
      timeout
    )
  end

  @doc "Sends one asynchronous Signal. Delivery is best effort under overload."
  @spec cast(server(), Signal.t()) :: :ok
  def cast(server, %Signal{} = signal) do
    :gen_statem.cast(server, {:signal, make_ref(), signal})
  end

  @doc "Stops one Agent Server through its normal OTP termination path."
  @spec stop(server(), term(), timeout()) :: :ok
  def stop(server, reason \\ :shutdown, timeout \\ 5_000) do
    :gen_statem.stop(server, Shutdown.normalize_reason(reason), timeout)
  end

  @doc "Returns one declared Plugin's owned field from the complete Agent state map."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000) when is_atom(plugin) do
    :gen_statem.call(server, {:plugin_state, plugin}, timeout)
  end

  @doc "Starts an asynchronous request for one Signal."
  @spec send_request(server(), Signal.t(), timeout()) :: term()
  def send_request(server, %Signal{} = signal, timeout \\ 5_000) do
    :gen_statem.send_request(
      server,
      {:signal, make_ref(), signal, AdmissionDeadline.new(timeout)}
    )
  end

  @doc "Receives the response for `send_request/3`."
  @spec receive_response(term(), timeout()) :: term()
  def receive_response(request_id, timeout \\ 5_000) do
    :gen_statem.receive_response(request_id, timeout)
  end

  @doc "Returns the current committed Agent value."
  @spec agent(server(), timeout()) :: Agent.t()
  def agent(server, timeout \\ 5_000), do: :gen_statem.call(server, :agent, timeout)

  @doc """
  Returns a narrow view of current Agent Server work.

  The result contains the runtime phase, Agent ID, commit revision, admission
  counts, lifecycle information, and a bounded active-Turn summary. The active
  summary is `nil` when no Turn is active. This function does not return the
  private `:gen_statem` state.
  """
  @spec status(server(), timeout()) :: map()
  def status(server, timeout \\ 5_000), do: :gen_statem.call(server, :status, timeout)

  @doc "Waits until Agent runtime children are ready."
  @spec await_ready(server(), timeout()) :: :ok | {:error, term()}
  def await_ready(server, timeout \\ 5_000) do
    :gen_statem.call(server, :await_ready, timeout)
  catch
    :exit, reason -> {:error, normalize_ready_error(reason)}
  end

  @doc "Cancels the active executable turn."
  @spec cancel(server(), timeout()) :: :ok | {:error, term()}
  def cancel(server, timeout \\ 5_000), do: :gen_statem.call(server, :cancel, timeout)

  @doc "Cancels one active executable Turn only when its stable id still matches."
  @spec cancel_turn(server(), String.t(), timeout()) :: :ok | {:error, term()}
  def cancel_turn(server, turn_id, timeout \\ 5_000) when is_binary(turn_id) do
    :gen_statem.call(server, {:cancel, turn_id}, timeout)
  end

  @doc """
  Enables or disables the bounded runtime event buffer for one Agent.

  Enabling the buffer records new events only. Disabling it clears all stored
  events. This setting does not change semantic log detail.
  """
  @spec set_debug(server(), boolean(), timeout()) :: :ok
  def set_debug(server, enabled, timeout \\ 5_000) when is_boolean(enabled) do
    :gen_statem.call(server, {:set_debug, enabled}, timeout)
  end

  @doc """
  Returns recent Agent runtime events in newest-first order.

  Use the `:limit` option to request fewer events than the configured
  `debug_max_events` value. Entries contain bounded identity, revision,
  Directive, timing, status, and safe error data. They do not contain Agent
  state, full Signals, raw errors, or complete Turn Outcome records.

  Returns `{:error, :debug_not_enabled}` when the buffer is off.
  """
  @spec recent_events(server(), keyword(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def recent_events(server, opts \\ [], timeout \\ 5_000) when is_list(opts) do
    :gen_statem.call(server, {:recent_events, opts}, timeout)
  end

  @doc "Returns the PID for an Agent id in one Registry."
  @spec whereis(module(), String.t(), keyword()) :: pid() | nil
  def whereis(registry, id, opts \\ []) when is_atom(registry) and is_binary(id) do
    key = RegistrationGuard.registry_key(id, Keyword.get(opts, :partition))

    case Registry.lookup(registry, key) do
      [{pid, :ready}] -> if Process.alive?(pid), do: pid
      [{_pid, _status}] -> nil
      [] -> nil
    end
  end

  @doc "Returns a Registry via tuple for an Agent id."
  @spec via_tuple(String.t(), module(), keyword()) :: {:via, Registry, {module(), term()}}
  def via_tuple(id, registry, opts \\ []) when is_binary(id) and is_atom(registry) do
    {:via, Registry,
     {registry, RegistrationGuard.registry_key(id, Keyword.get(opts, :partition))}}
  end

  @doc """
  Returns true when the Agent Server is alive.

  Remote checks have a one-second limit. False means that liveness could not
  be confirmed; it does not prove process exit during a network failure.
  """
  @spec alive?(server()) :: boolean()
  def alive?(server) when is_pid(server) and node(server) == node(), do: Process.alive?(server)

  def alive?(server) when is_pid(server) do
    :erpc.call(node(server), Process, :alive?, [server], 1_000)
  catch
    _kind, _reason -> false
  end

  def alive?(server) do
    case GenServer.whereis(server) do
      pid when is_pid(pid) -> alive?(pid)
      _value -> false
    end
  end

  @doc "Attaches an owner process and prevents idle hibernation."
  @spec attach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def attach(server, owner_pid \\ self(), timeout \\ 5_000) when is_pid(owner_pid) do
    :gen_statem.call(server, {:attach, owner_pid}, timeout)
  end

  @doc "Detaches an owner process. The idle timer starts after the last detach."
  @spec detach(server(), pid(), timeout()) :: :ok | {:error, term()}
  def detach(server, owner_pid \\ self(), timeout \\ 5_000) when is_pid(owner_pid) do
    :gen_statem.call(server, {:detach, owner_pid}, timeout)
  end

  @doc "Resets the idle timer without attaching an owner process."
  @spec touch(server()) :: :ok
  def touch(server), do: :gen_statem.cast(server, :touch)

  @doc false
  @spec adopt_parent(server(), ParentRef.t()) :: {:ok, map()} | {:error, term()}
  def adopt_parent(server, %ParentRef{} = parent) do
    with {:ok, parent} <- ParentRef.new(parent) do
      :gen_statem.call(server, {:adopt_parent, parent})
    end
  end

  @doc false
  def creation_info(server) do
    {:ok, :gen_statem.call(server, :creation_info, 1_000)}
  catch
    :exit, reason -> {:uncertain, {:child_identity_unavailable, reason}}
  end

  @doc "Adopts one orphaned Agent as a tracked child."
  @spec adopt_child(server(), pid() | String.t(), term(), map()) :: :ok | {:error, term()}
  def adopt_child(server, child, tag, meta \\ %{}) do
    :gen_statem.call(server, {:adopt_child, child, tag, meta})
  end

  @doc """
  Stops one tracked child Agent.

  A supervised child exits with `:shutdown` when its DynamicSupervisor removes
  it. The reason applies only if the child is no longer in that supervisor or
  is a standalone tracked process.
  """
  @spec stop_child(server(), term(), term()) :: :ok | {:error, term()}
  def stop_child(server, tag, reason \\ :normal) do
    :gen_statem.call(server, {:stop_child, tag, reason})
  end

  @doc "Returns a public view of tracked Agent and Plugin children."
  @spec children(server(), timeout()) :: map()
  def children(server, timeout \\ 5_000), do: :gen_statem.call(server, :children, timeout)

  @doc """
  Returns the committed Agent and its commit revision as `:state_version`.

  Every successful Turn increases the revision once, even when the Agent state
  is unchanged. A failure before commit preserves both state and revision.
  A Directive failure after commit does not undo that commit.
  """
  @spec snapshot(server(), timeout()) :: map()
  def snapshot(server, timeout \\ 5_000), do: :gen_statem.call(server, :snapshot, timeout)

  @doc """
  Runs one upgrade operation after the Agent Server becomes idle.

  The Server postpones this call while a Turn or its Directives are active.
  Signals that arrive after the upgrade request stay behind it in the OTP event
  order. The operation must return `:ok` or `{:error, reason}` and must not call
  this Agent Server synchronously.

  This boundary coordinates a code installation. It does not pin arbitrary
  BEAM module loads that happen outside this call.
  """
  @spec upgrade(server(), upgrade_operation()) :: :ok | {:error, term()}
  def upgrade(server, operation), do: upgrade(server, operation, 5_000)

  @spec upgrade(server(), upgrade_operation(), timeout()) :: :ok | {:error, term()}
  def upgrade(server, operation, timeout) when is_function(operation, 0) do
    :gen_statem.call(server, {:upgrade_operation, operation}, timeout)
  end

  @doc """
  Replaces the live Agent definition with validated migrated state.

  The migration runs only while the Server is idle. It receives the current
  committed Agent and must return one complete state map. The target definition
  must keep the same Plugin declarations because this operation does not replace
  Plugin runtime structure. A successful replacement advances the state version
  once and writes the required checkpoint before the new Agent is visible.

  A durable replacement that changes the Agent module requires a stable Jido
  namespace. Compatible module-and-ID persistence keys cannot change modules in
  one atomic write.
  """
  @spec upgrade(server(), module(), state_migration()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration),
    do: upgrade(server, target_module, migration, 5_000)

  @spec upgrade(server(), module(), state_migration(), timeout()) ::
          {:ok, Agent.t()} | {:error, term()}
  def upgrade(server, target_module, migration, timeout)
      when is_atom(target_module) and is_function(migration, 1) do
    :gen_statem.call(server, {:upgrade_definition, target_module, migration}, timeout)
  end

  @doc "Persists and stops one Agent Server after it becomes idle."
  @spec hibernate(server(), keyword()) :: :ok | {:error, term()}
  def hibernate(server, opts \\ []) when is_list(opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)

    case resolve_server_pid(server) do
      pid when is_pid(pid) -> hibernate_pid(pid, opts, timeout)
      nil -> {:error, :not_running}
    end
  end

  defp hibernate_pid(pid, opts, timeout) do
    ref = Process.monitor(pid)

    try do
      case :gen_statem.call(pid, {:hibernate, opts}, timeout) do
        :ok ->
          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            timeout -> {:error, :timeout}
          end

        error ->
          error
      end
    catch
      :exit, reason -> {:error, normalize_hibernate_error(reason)}
    after
      Process.demonitor(ref, [:flush])
    end
  end

  defp resolve_server_pid(server) do
    GenServer.whereis(server)
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(opts), do: ServerLifecycle.init(opts)

  @impl true
  def handle_event({:call, _from}, :await_ready, :initializing, %State{}) do
    {:keep_state_and_data, [:postpone]}
  end

  def handle_event({:call, from}, :await_ready, _phase, %State{} = data) do
    case PluginLifecycle.readiness_status(data) do
      :ready -> {:keep_state_and_data, [{:reply, from, :ok}]}
      {:error, reason} -> {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  @impl true
  def handle_event({:call, from}, :agent, _phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, data.agent}]}
  end

  def handle_event({:call, from}, {:plugin_state, plugin}, _phase, %State{} = data) do
    reply =
      case Enum.find(data.plugin_specs, &(&1.module == plugin)) do
        nil -> {:error, {:plugin_not_declared, plugin}}
        spec -> {:ok, PluginLifecycle.plugin_state_value(data.agent.state, spec.state_key)}
      end

    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def handle_event({:call, from}, :status, phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, Inspection.status(phase, data)}]}
  end

  def handle_event({:call, from}, :creation_info, _phase, %State{} = data) do
    info = %{
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      partition: data.partition,
      activation_id: data.activation_id,
      parent: data.parent
    }

    {:keep_state_and_data, [{:reply, from, info}]}
  end

  def handle_event({:call, from}, :children, _phase, %State{} = data) do
    children = Map.new(data.children, fn {key, child} -> {key, Inspection.child(child)} end)
    {:keep_state_and_data, [{:reply, from, children}]}
  end

  def handle_event({:call, from}, :snapshot, _phase, %State{} = data) do
    snapshot = %{
      agent: data.agent,
      state_version: data.state_version
    }

    {:keep_state_and_data, [{:reply, from, snapshot}]}
  end

  def handle_event(
        {:call, from},
        {:upgrade_operation, operation},
        :idle,
        %State{} = data
      ) do
    reply = Upgrade.operation(operation)
    {:keep_state, Idle.maybe_start_idle_timer(data, :idle), [{:reply, from, reply}]}
  end

  def handle_event(
        {:call, from},
        {:upgrade_definition, target_module, migration},
        :idle,
        %State{} = data
      ) do
    Upgrade.upgrade_definition(from, target_module, migration, data)
  end

  def handle_event({:call, _from}, {:upgrade_operation, _operation}, phase, %State{})
      when phase in [:initializing, :admitting, :running, :directing] do
    {:keep_state_and_data, [:postpone]}
  end

  def handle_event(
        {:call, _from},
        {:upgrade_definition, _target_module, _migration},
        phase,
        %State{}
      )
      when phase in [:initializing, :admitting, :running, :directing] do
    {:keep_state_and_data, [:postpone]}
  end

  def handle_event({:call, from}, {:hibernate, opts}, :idle, %State{} = data) do
    case Storage.persist_agent(data, data.agent, data.state_version, :hibernate, opts) do
      :ok ->
        {:stop_and_reply, {:shutdown, :hibernate}, [{:reply, from, :ok}], data}

      {:error, _reason} = error ->
        {:keep_state_and_data, [{:reply, from, error}]}
    end
  end

  def handle_event({:call, _from}, {:hibernate, _opts}, phase, %State{})
      when phase in [:admitting, :running, :directing] do
    {:keep_state_and_data, [:postpone]}
  end

  def handle_event({:call, _} = type, {:attach, _} = event, phase, %State{} = data),
    do: Idle.handle_event(type, event, phase, data)

  def handle_event({:call, _} = type, {:detach, _} = event, phase, %State{} = data),
    do: Idle.handle_event(type, event, phase, data)

  def handle_event(:cast, :touch, phase, %State{} = data),
    do: Idle.handle_event(:cast, :touch, phase, data)

  def handle_event({:call, from}, {:set_debug, enabled}, _phase, %State{} = data)
      when is_boolean(enabled) do
    next_data = %{
      data
      | debug: enabled,
        debug_events: if(enabled, do: data.debug_events, else: [])
    }

    {:keep_state, next_data, [{:reply, from, :ok}]}
  end

  def handle_event({:call, from}, {:recent_events, opts}, _phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, Inspection.recent_events(data, opts)}]}
  end

  def handle_event({:call, from}, {:adopt_parent, %ParentRef{} = parent}, _phase, data) do
    case ChildLifecycle.attach_parent(data, parent) do
      {:ok, next_data} ->
        reply = ChildLifecycle.relationship_info(next_data)
        {:keep_state, next_data, [{:reply, from, {:ok, reply}}]}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:adopt_child, child, tag, meta}, _phase, data) do
    directive = %Directive.AdoptChild{child: child, tag: tag, meta: meta}
    ChildOperations.handle_child_directive_call(directive, from, data)
  end

  def handle_event({:call, from}, {:stop_child, tag, reason}, _phase, data) do
    directive = %Directive.StopChild{tag: tag, reason: reason}
    ChildOperations.handle_child_directive_call(directive, from, data)
  end

  def handle_event(:info, {:signal, %Signal{} = signal}, _phase, %State{}) do
    cast(self(), signal)
    :keep_state_and_data
  end

  def handle_event(:internal, :bootstrap, :initializing, %State{} = data),
    do: ServerLifecycle.handle_event(:internal, :bootstrap, :initializing, data)

  def handle_event({:call, _} = type, event, phase, %State{} = data)
      when event == :cancel or (is_tuple(event) and elem(event, 0) == :cancel),
      do: Cancellation.handle_event(type, event, phase, data)

  def handle_event({:call, _} = type, {:signal, _, %Signal{}, _} = event, phase, %State{} = data),
    do: Admission.handle_event(type, event, phase, data)

  def handle_event(
        {:call, _} = type,
        {:signal, _, %Signal{}, _, _} = event,
        phase,
        %State{} = data
      ),
      do: Admission.handle_event(type, event, phase, data)

  def handle_event(:cast, {:signal, _, %Signal{}} = event, phase, %State{} = data),
    do: Admission.handle_event(:cast, event, phase, data)

  def handle_event(:info, message, phase, %State{} = data), do: route_info(message, phase, data)

  def handle_event(:internal, {:after_commit, _, _} = event, :directing, %State{} = data),
    do: PostCommit.handle_event(:internal, event, :directing, data)

  def handle_event(:internal, {:handle_directives, _, _} = event, :directing, %State{} = data),
    do: PostCommit.handle_event(:internal, event, :directing, data)

  def handle_event({:call, from}, _request, _phase, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :unknown_call}}]}
  end

  def handle_event(_event_type, _event, _phase, %State{}), do: :keep_state_and_data

  @impl true
  def terminate(reason, phase, data), do: ServerLifecycle.terminate(reason, phase, data)

  defp route_info({:plugin_readiness, _, _} = message, :initializing, data),
    do: ServerLifecycle.handle_event(:info, message, :initializing, data)

  defp route_info({:timeout, _, {:plugin_readiness_timeout, _}} = message, :initializing, data),
    do: ServerLifecycle.handle_event(:info, message, :initializing, data)

  defp route_info({:agent_child_online, _, _, _, _, _, _} = message, phase, data),
    do: ChildLifecycle.handle_event(:info, message, phase, data)

  defp route_info({:jido_registry_restarted, pid}, phase, data),
    do: ServerLifecycle.recover_registry_registration(pid, phase, data)

  defp route_info({:jido_registry_recover, pid}, phase, data),
    do: ServerLifecycle.recover_registry_registration(pid, phase, data)

  defp route_info({:plugin_runtime_restarting, _, _} = message, phase, data),
    do: PluginLifecycle.handle_event(:info, message, phase, data)

  defp route_info({:plugin_runtime_bootstrap, _, _, _} = message, phase, data),
    do: PluginLifecycle.handle_event(:info, message, phase, data)

  defp route_info({:plugin_runtime_ready, _, _, _} = message, phase, data),
    do: PluginLifecycle.handle_event(:info, message, phase, data)

  defp route_info({ref, result} = message, phase, data) when is_reference(ref) do
    cond do
      phase == :admitting and TaskSupport.task_ref?(data.admission_task, ref) ->
        Turn.admission_result(result, data)

      phase == :directing and TaskSupport.task_ref?(data.commit_task, ref) ->
        PostCommit.commit_result(result, data)

      phase == :directing and TaskSupport.task_ref?(data.directive_task, ref) ->
        PostCommit.directive_result(result, data)

      Map.has_key?(data.error_policy_tasks, ref) ->
        FailurePolicy.task_result(ref, result, data)

      phase == :cancelling and TaskSupport.task_ref?(data.cancel_task, ref) ->
        Cancellation.task_result(result, data)

      true ->
        fallback_info(message, phase, data)
    end
  end

  defp route_info({:timeout, timer, payload} = message, phase, data),
    do: route_timeout(message, timer, payload, phase, data)

  defp route_info({:DOWN, ref, :process, pid, reason} = message, phase, data) do
    cond do
      phase == :initializing and match?(%{ref: ^ref}, data.plugin_bootstrap) ->
        ServerLifecycle.handle_event(:info, message, phase, data)

      phase == :admitting and TaskSupport.task_ref?(data.admission_task, ref) ->
        Turn.admission_down(reason, data)

      phase == :directing and TaskSupport.task_ref?(data.commit_task, ref) ->
        PostCommit.commit_down(reason, data)

      phase == :directing and TaskSupport.task_ref?(data.directive_task, ref) ->
        PostCommit.directive_down(reason, data)

      Map.has_key?(data.error_policy_tasks, ref) ->
        FailurePolicy.task_down(ref, reason, data)

      phase == :cancelling and TaskSupport.task_ref?(data.cancel_task, ref) ->
        Cancellation.task_down(reason, data)

      phase == :running and
          match?(
            %ActiveTurn{exec_handle: %ExecutionAdapter{pid: ^pid, monitor_ref: ^ref}},
            data.active
          ) ->
        Turn.adapter_down(reason, data)

      phase == :cancelling ->
        {:keep_state_and_data, [:postpone]}

      true ->
        handle_process_down(ref, pid, reason, phase, data)
    end
  end

  defp route_info({tag, _, _} = message, :running, data)
       when tag in [:jido_exec_adapter_started, :jido_exec_adapter_start_failed],
       do: Turn.handle_event(:info, message, :running, data)

  defp route_info({tag, _, _, _} = message, :running, data)
       when tag in [:jido_exec_adapter_callback_started, :jido_exec_adapter_callback_result],
       do: Turn.handle_event(:info, message, :running, data)

  defp route_info(message, phase, data), do: fallback_info(message, phase, data)

  defp route_timeout(message, timer, {:turn_timeout, turn_id}, phase, data)
       when phase in [:admitting, :running] do
    if match?(%ActiveTurn{turn_id: ^turn_id, timeout_timer: ^timer}, data.active) do
      if phase == :admitting,
        do: Cancellation.timeout_admission(data),
        else: Cancellation.timeout_execution(data)
    else
      fallback_info(message, phase, data)
    end
  end

  defp route_timeout(message, timer, {:after_commit_timeout, ref}, :directing, data) do
    if TaskSupport.task_ref?(data.commit_task, ref) and data.commit_task.timer == timer,
      do: PostCommit.commit_timeout(data),
      else: fallback_info(message, :directing, data)
  end

  defp route_timeout(message, timer, {:directive_timeout, ref}, :directing, data) do
    if TaskSupport.task_ref?(data.directive_task, ref) and data.directive_task.timer == timer,
      do: PostCommit.directive_timeout(data),
      else: fallback_info(message, :directing, data)
  end

  defp route_timeout(message, timer, {:error_policy_dispatch_timeout, ref}, phase, data) do
    if Map.has_key?(data.error_policy_tasks, ref),
      do: FailurePolicy.task_timeout(ref, timer, data),
      else: fallback_info(message, phase, data)
  end

  defp route_timeout(_message, timer, {:exec_cancel_timeout, ref}, :cancelling, data) do
    if TaskSupport.task_ref?(data.cancel_task, ref) and data.cancel_task.timer == timer,
      do: Cancellation.task_timeout(data),
      else: {:keep_state_and_data, [:postpone]}
  end

  defp route_timeout(message, _timer, {:exec_adapter_timeout, _, _, _}, :running, data),
    do: Turn.handle_event(:info, message, :running, data)

  defp route_timeout(message, _timer, :agent_idle_timeout, phase, data) when phase != :cancelling,
    do: Idle.handle_event(:info, message, phase, data)

  defp route_timeout(message, _timer, _payload, phase, data),
    do: fallback_info(message, phase, data)

  defp fallback_info(_message, :cancelling, %State{}),
    do: {:keep_state_and_data, [:postpone]}

  defp fallback_info(message, :running, %State{active: %ActiveTurn{}} = data),
    do: Turn.handle_exec_message(message, data)

  defp fallback_info(_message, _phase, %State{}), do: :keep_state_and_data

  defp handle_process_down(ref, pid, reason, phase, %State{} = data) do
    case Map.fetch(data.attachments, pid) do
      {:ok, ^ref} ->
        next_data =
          data
          |> Idle.remove_attachment(pid)
          |> Idle.maybe_start_idle_timer(phase)

        {:keep_state, next_data}

      _other ->
        cond do
          match?(%ParentRef{ref: ^ref, pid: ^pid}, data.parent) ->
            ChildLifecycle.handle_parent_down(reason, data)

          child_entry = State.child_by_ref(data, ref) ->
            ChildLifecycle.handle_child_down(child_entry, pid, reason, data)

          phase == :running and match?(%ActiveTurn{}, data.active) ->
            Turn.handle_exec_message({:DOWN, ref, :process, pid, reason}, data)

          true ->
            :keep_state_and_data
        end
    end
  end

  defp server_name(%Options{name: name}) when not is_nil(name), do: normalize_name(name)

  defp server_name(%Options{register: true, registry: registry, agent: agent} = opts)
       when is_atom(registry) and not is_nil(registry) do
    via_tuple(agent.id, registry, partition: opts.partition)
  end

  defp server_name(%Options{}), do: nil

  defp startup_result(pid, reply) do
    monitor = Process.monitor(pid)

    try do
      receive do
        {^reply, :ok} ->
          {:ok, pid}

        {^reply, {:error, reason}} ->
          {:error, reason}

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          receive do
            {^reply, :ok} -> {:ok, pid}
            {^reply, {:error, _reason} = error} -> error
          after
            0 -> {:error, ServerLifecycle.normalize_startup_error(reason)}
          end
      after
        5_000 ->
          if Process.alive?(pid), do: Process.exit(pid, :shutdown)
          {:error, :timeout}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp normalize_ready_error(
         {{:shutdown, {:bootstrap_failed, reason}}, {:gen_statem, :call, _details}}
       ),
       do: {:bootstrap_failed, reason}

  defp normalize_ready_error({:timeout, {:gen_statem, :call, _details}}), do: :timeout
  defp normalize_ready_error({:noproc, {:gen_statem, :call, _details}}), do: :not_running
  defp normalize_ready_error(reason), do: reason

  defp normalize_hibernate_error({:timeout, {:gen_statem, :call, _details}}), do: :timeout
  defp normalize_hibernate_error({:noproc, {:gen_statem, :call, _details}}), do: :not_running
  defp normalize_hibernate_error(:noproc), do: :not_running
  defp normalize_hibernate_error(reason), do: reason

  defp normalize_name(name) when is_atom(name), do: {:local, name}
  defp normalize_name({:global, _term} = name), do: name
  defp normalize_name({:via, _module, _term} = name), do: name

  defp normalize_name(name) do
    raise ArgumentError,
          "Agent Server name must be an atom, :global tuple, or :via tuple, got: #{inspect(name)}"
  end
end
