defmodule Jido.AgentServer do
  @moduledoc """
  The responsive OTP owner for one live `Jido.Agent`.

  This Server uses four active `:gen_statem` states: `:idle`, `:admitting`,
  `:running`, and `:directing`. One Signal selects one Action or Flow. Live
  Plugin admission, `Jido.Exec`, and outbound Plugin work run asynchronously.
  The Server commits only the terminal complete state result. It then
  interprets returned Directives in list order before it accepts the next
  Signal.

  The Agent state commit is atomic. Turn execution is not a transaction across
  external systems: an Action or Flow can complete I/O before returning an
  error. That failure preserves committed Agent state but does not undo the
  I/O. Applications own external idempotency and recovery.

  Signals that arrive during a turn are postponed by OTP. OTP retains each full
  postponed event. The Server keeps bounded admission tokens so it can reject
  excess work. This limit does not bound messages that have not yet reached the
  state-machine callback.

  The Server assigns one stable UUID7 to each admitted Turn. It keeps a private
  `ActiveTurn` until execution and all post-commit Directives stop. It then
  creates one public `Jido.Agent.Turn.Outcome`. A custom two-argument error
  policy receives the original error and this Outcome. When debug mode is on,
  the terminal debug event also contains the Outcome.

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

  Exec roots, Action tasks, Flow tasks, and asynchronous Directives run under
  the Jido instance Task Supervisor. The Server also links each Exec root to
  itself. Active execution cannot outlive its Agent owner.
  """

  @behaviour :gen_statem

  require Logger

  alias Jido.Agent
  alias Jido.Agent.Command.Runner
  alias Jido.Agent.Directive
  alias Jido.Agent.Turn.Outcome
  alias Jido.Plugin
  alias Jido.Plugin.DirectiveContext, as: PluginDirectiveContext
  alias Jido.Plugin.SignalContext, as: PluginSignalContext

  alias Jido.AgentServer.{
    ActiveTurn,
    ChildInfo,
    DirectiveContext,
    DirectiveRuntime,
    Options,
    ParentRef,
    PluginLifecycle,
    RuntimeCheckpoint,
    State
  }

  alias Jido.AgentServer.Signal.{ChildExit, Orphaned}
  alias Jido.Error
  alias Jido.Observe
  alias Jido.Signal
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  @type server :: pid() | atom() | {:global, term()} | {:via, module(), term()}
  @type signal_result :: {:ok, Agent.t()} | {:error, term()}

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

  Caller context passes through Plugin admission and preparation to execution.
  It belongs to this Turn, including its post-commit Plugin work. Jido does not
  add it to Signal data, Agent or Plugin state, persistence, or emitted Signals.
  Application code must select any values it wants to store or emit.

  A durable revision conflict returns `{:error, {:persistence_failed, :conflict}}`
  before live state changes or Directives run. The configured error policy
  decides whether the Server continues or stops. It does not reload or retry
  the command automatically; external Action work may already have completed.
  Uncertain persistence commit errors stop the Server before more work can run.
  The write can have completed even if its reply was lost. A new activation
  must restore the stored state before it can continue.

  `:agent_id`, `:agent_state`, and `:signal` are reserved execution keys. The
  Server supplies its own `:jido` and `:partition` values. Caller timeout stops
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
    with {:ok, opts} <- validate_keyword(opts, :call),
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
      {:signal, make_ref(), signal, admission_deadline(timeout), context},
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
    :gen_statem.stop(server, normalize_stop_reason(reason), timeout)
  end

  @doc "Returns the current portable state owned by one declared Plugin."
  @spec plugin_state(server(), module(), timeout()) :: {:ok, term()} | {:error, term()}
  def plugin_state(server, plugin, timeout \\ 5_000) when is_atom(plugin) do
    :gen_statem.call(server, {:plugin_state, plugin}, timeout)
  end

  @doc "Starts an asynchronous request for one Signal."
  @spec send_request(server(), Signal.t(), timeout()) :: term()
  def send_request(server, %Signal{} = signal, timeout \\ 5_000) do
    :gen_statem.send_request(
      server,
      {:signal, make_ref(), signal, admission_deadline(timeout)}
    )
  end

  @doc "Receives the response for `send_request/3`."
  @spec receive_response(term(), timeout()) :: term()
  def receive_response(request_id, timeout \\ 5_000) do
    :gen_statem.receive_response(request_id, timeout)
  end

  @doc "Returns the current committed Agent."
  @spec agent(server(), timeout()) :: Agent.t()
  def agent(server, timeout \\ 5_000), do: :gen_statem.call(server, :agent, timeout)

  @doc "Returns a narrow view of the Agent turn state."
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

  @doc "Enables or disables the bounded Agent runtime event buffer."
  @spec set_debug(server(), boolean(), timeout()) :: :ok
  def set_debug(server, enabled, timeout \\ 5_000) when is_boolean(enabled) do
    :gen_statem.call(server, {:set_debug, enabled}, timeout)
  end

  @doc "Returns recent Agent runtime events in newest-first order."
  @spec recent_events(server(), keyword(), timeout()) :: {:ok, [map()]} | {:error, term()}
  def recent_events(server, opts \\ [], timeout \\ 5_000) when is_list(opts) do
    :gen_statem.call(server, {:recent_events, opts}, timeout)
  end

  @doc "Returns the PID for an Agent id in one Registry."
  @spec whereis(module(), String.t(), keyword()) :: pid() | nil
  def whereis(registry, id, opts \\ []) when is_atom(registry) and is_binary(id) do
    key = registry_key(id, Keyword.get(opts, :partition))

    case Registry.lookup(registry, key) do
      [{pid, _value}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @doc "Returns a Registry via tuple for an Agent id."
  @spec via_tuple(String.t(), module(), keyword()) :: {:via, Registry, {module(), term()}}
  def via_tuple(id, registry, opts \\ []) when is_binary(id) and is_atom(registry) do
    {:via, Registry, {registry, registry_key(id, Keyword.get(opts, :partition))}}
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
    :gen_statem.call(server, {:adopt_parent, parent})
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

  @doc "Stops one tracked child Agent."
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

  @doc "Persists and stops one Agent Server after it becomes idle."
  @spec hibernate(server(), keyword()) :: :ok | {:error, term()}
  def hibernate(server, opts \\ []) when is_list(opts) do
    {timeout, opts} = Keyword.pop(opts, :timeout, 5_000)
    pid = GenServer.whereis(server)
    ref = Process.monitor(pid)

    try do
      case :gen_statem.call(pid, {:hibernate, opts}, timeout) do
        :ok ->
          receive do
            {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
          after
            timeout -> exit({:timeout, {__MODULE__, :hibernate, [server, opts]}})
          end

        error ->
          error
      end
    after
      Process.demonitor(ref, [:flush])
    end
  end

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(%Options{} = opts), do: init({opts, nil})

  def init({%Options{} = opts, startup_reply}) do
    Process.flag(:trap_exit, true)

    with {:ok, restored_agent, restored_version} <- restore_initial_agent(opts),
         {:ok, agent} <- Agent.validate_instance(restored_agent),
         {:ok, plugin_specs} <- Plugin.normalize_all(agent.plugins),
         {:ok, exec_module} <- validate_exec_module(opts.exec_module),
         {:ok, exec_opts} <- validate_keyword(opts.exec_opts, :exec_opts),
         {:ok, max_postponed_signals} <-
           validate_limit(opts.max_postponed_signals, :max_postponed_signals),
         {:ok, max_directives_per_turn} <-
           validate_limit(opts.max_directives_per_turn, :max_directives_per_turn) do
      parent = opts |> restore_parent(agent) |> monitor_parent()

      data = %State{
        agent: agent,
        plugin_specs: plugin_specs,
        jido: opts.jido,
        partition: opts.partition,
        registry: opts.registry,
        registered?: opts.register,
        exec_module: exec_module,
        exec_opts: exec_opts,
        max_postponed_signals: max_postponed_signals,
        postponed_tokens: MapSet.new(),
        max_directives_per_turn: max_directives_per_turn,
        directive_timeout: opts.directive_timeout,
        default_dispatch: opts.default_dispatch,
        error_policy: opts.error_policy,
        error_count: 0,
        parent: parent,
        orphaned_from: nil,
        children: %{},
        on_parent_death: opts.on_parent_death,
        pool: opts.pool,
        pool_key: opts.pool_key,
        idle_timeout: opts.idle_timeout,
        persistence: opts.persistence,
        attachments: %{},
        idle_timer: nil,
        spawn_fun: opts.spawn_fun,
        debug: opts.debug,
        debug_events: [],
        debug_max_events: opts.debug_max_events,
        state_version: restored_version,
        activation_id: Signal.ID.generate!(),
        active: nil,
        plugin_bootstrap: nil,
        startup_reply: startup_reply,
        admission_task: nil,
        directive_task: nil
      }

      span =
        AgentTelemetry.start(
          :lifecycle,
          Map.put(AgentTelemetry.lifecycle_metadata(data), :operation, :activate)
        )

      {:ok, :initializing, %{data | activation_span: span},
       [{:next_event, :internal, :bootstrap}]}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def handle_event(:internal, :bootstrap, :initializing, %State{} = data) do
    case PluginLifecycle.start_all(data) do
      {:ok, data} ->
        {:keep_state, start_plugin_readiness(data)}

      {:error, reason, data} ->
        PluginLifecycle.stop_all(data, :shutdown)
        {:stop, {:shutdown, {:bootstrap_failed, reason}}, data}
    end
  end

  def handle_event(
        :info,
        {:plugin_readiness, token, :ok},
        :initializing,
        %State{plugin_bootstrap: %{token: token, ref: ref}} = data
      ) do
    Process.demonitor(ref, [:flush])

    AgentTelemetry.finish(data.activation_span, %{status: :ok}, %{
      state_version: data.state_version
    })

    notify_startup(data, :ok)
    data = %{data | plugin_bootstrap: nil, activation_span: nil, startup_reply: nil}
    notify_parent_online(data)
    {:next_state, :idle, maybe_start_idle_timer(data, :idle)}
  end

  def handle_event(
        :info,
        {:plugin_readiness, token, {:error, reason}},
        :initializing,
        %State{plugin_bootstrap: %{token: token, ref: ref}} = data
      ) do
    Process.demonitor(ref, [:flush])
    {:stop, {:shutdown, {:plugin_readiness_failed, reason}}, %{data | plugin_bootstrap: nil}}
  end

  def handle_event({:call, _from}, :await_ready, :initializing, %State{}) do
    {:keep_state_and_data, [:postpone]}
  end

  def handle_event({:call, from}, :await_ready, _phase, %State{}) do
    {:keep_state_and_data, [{:reply, from, :ok}]}
  end

  @impl true
  def handle_event({:call, from}, :agent, _phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, data.agent}]}
  end

  def handle_event({:call, from}, {:plugin_state, plugin}, _phase, %State{} = data) do
    reply =
      case Enum.find(data.plugin_specs, &(&1.module == plugin)) do
        nil -> {:error, {:plugin_not_declared, plugin}}
        spec -> {:ok, plugin_state_value(data.agent.state, spec.state_key)}
      end

    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def handle_event({:call, from}, :status, phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, public_status(phase, data)}]}
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
    children = Map.new(data.children, fn {key, child} -> {key, public_child(child)} end)
    {:keep_state_and_data, [{:reply, from, children}]}
  end

  def handle_event({:call, from}, :snapshot, _phase, %State{} = data) do
    snapshot = %{
      agent: data.agent,
      state_version: data.state_version
    }

    {:keep_state_and_data, [{:reply, from, snapshot}]}
  end

  def handle_event({:call, from}, {:hibernate, opts}, :idle, %State{} = data) do
    case persist_agent(data, data.agent, data.state_version, :hibernate, opts) do
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

  def handle_event({:call, from}, {:attach, owner_pid}, _phase, %State{} = data) do
    case attach_owner(data, owner_pid) do
      {:ok, next_data} ->
        {:keep_state, next_data, [{:reply, from, :ok}]}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:detach, owner_pid}, phase, %State{} = data) do
    next_data = data |> detach_owner(owner_pid) |> maybe_start_idle_timer(phase)
    {:keep_state, next_data, [{:reply, from, :ok}]}
  end

  def handle_event(:cast, :touch, phase, %State{} = data) do
    {:keep_state, data |> cancel_idle_timer() |> maybe_start_idle_timer(phase)}
  end

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
    if data.debug do
      limit = opts |> Keyword.get(:limit, data.debug_max_events) |> normalize_event_limit()
      {:keep_state_and_data, [{:reply, from, {:ok, Enum.take(data.debug_events, limit)}}]}
    else
      {:keep_state_and_data, [{:reply, from, {:error, :debug_not_enabled}}]}
    end
  end

  def handle_event({:call, from}, {:adopt_parent, %ParentRef{} = parent}, _phase, data) do
    case attach_parent(data, parent) do
      {:ok, next_data} ->
        reply = relationship_info(next_data)
        {:keep_state, next_data, [{:reply, from, {:ok, reply}}]}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:adopt_child, child, tag, meta}, _phase, data) do
    directive = %Directive.AdoptChild{child: child, tag: tag, meta: meta}

    case DirectiveRuntime.handle(directive, directive_context(data), data) do
      {:ok, next_data} -> {:keep_state, next_data, [{:reply, from, :ok}]}
      {:error, reason, _next_data} -> {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:stop_child, tag, reason}, _phase, data) do
    directive = %Directive.StopChild{tag: tag, reason: reason}

    case DirectiveRuntime.handle(directive, directive_context(data), data) do
      {:ok, next_data} ->
        {:keep_state, next_data, [{:reply, from, :ok}]}

      {:error, error, _next_data} ->
        {:keep_state_and_data, [{:reply, from, {:error, error}}]}
    end
  end

  def handle_event({:call, from}, :cancel, :idle, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :idle}}]}
  end

  def handle_event({:call, from}, :cancel, :admitting, %State{} = data) do
    cancel_admission(from, data)
  end

  def handle_event({:call, from}, :cancel, :running, %State{} = data) do
    cancel_active(from, data)
  end

  def handle_event({:call, from}, :cancel, :directing, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :directing}}]}
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, :idle, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  def handle_event(
        {:call, from},
        {:cancel, turn_id},
        :admitting,
        %State{active: %ActiveTurn{turn_id: turn_id}} = data
      ) do
    cancel_admission(from, data)
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, :admitting, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  def handle_event(
        {:call, from},
        {:cancel, turn_id},
        :running,
        %State{active: %ActiveTurn{turn_id: turn_id}} = data
      ) do
    cancel_active(from, data)
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, :running, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, :directing, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  def handle_event({:call, from}, {:signal, token, %Signal{} = signal, deadline}, phase, data) do
    handle_event({:call, from}, {:signal, token, signal, deadline, %{}}, phase, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :initializing,
        %State{} = data
      ) do
    postpone_call(from, token, signal, deadline, data)
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :initializing, %State{} = data) do
    postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, context},
        :idle,
        %State{} = data
      ) do
    data = forget_postponed(data, token)

    if admission_expired?(deadline) do
      {:keep_state, data, [{:reply, from, {:error, :admission_timeout}}]}
    else
      start_turn(signal, from, context, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :idle, %State{} = data) do
    start_turn(signal, nil, %{}, forget_postponed(data, token))
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :admitting,
        %State{} = data
      ) do
    if reentrant_admission_call?(from, data.admission_task) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_admission}}]}
    else
      postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :admitting, %State{} = data) do
    postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :running,
        %State{} = data
      ) do
    if reentrant_turn_call?(from, data.active) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_turn}}]}
    else
      postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :running, %State{} = data) do
    postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :directing,
        %State{} = data
      ) do
    if reentrant_directive_call?(from, data.directive_task) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_directive}}]}
    else
      postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :directing, %State{} = data) do
    postpone_cast(token, signal, data)
  end

  def handle_event(:info, {:signal, %Signal{} = signal}, _phase, %State{}) do
    cast(self(), signal)
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:agent_child_online, pid, child_id, _child_module, _child_partition, tag, _meta},
        _phase,
        %State{} = data
      ) do
    case verify_child_online(pid, child_id, tag, data) do
      {:ok, info} ->
        {:keep_state, track_online_child(data, pid, info)}

      {:error, _reason} ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:plugin_runtime_ready, lifecycle_pid, plugin, runtime_pid},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    case State.child(data, key) do
      %ChildInfo{lifecycle_pid: ^lifecycle_pid} = child ->
        {:keep_state, State.add_child(data, key, %{child | pid: runtime_pid})}

      _child ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        :initializing,
        %State{plugin_bootstrap: %{ref: ref}} = data
      ) do
    {:stop, {:shutdown, {:plugin_readiness_failed, reason}}, %{data | plugin_bootstrap: nil}}
  end

  def handle_event(
        :info,
        {ref, result},
        :admitting,
        %State{admission_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    Process.demonitor(ref, [:flush])
    cancel_task_timer(pending.timer)
    data = %{data | admission_task: nil}

    case result do
      {:ok, %Jido.Agent.Command{} = command} -> begin_turn_execution(command, data)
      {:error, reason} -> fail_turn(reason, :prepare, data)
      other -> fail_turn({:invalid_plugin_admission_result, other}, :prepare, data)
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        :admitting,
        %State{admission_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    cancel_task_timer(pending.timer)
    data = %{data | admission_task: nil}

    error =
      Error.execution_error("Agent Plugin admission task exited",
        details: %{reason: reason}
      )

    fail_turn(error, :prepare, data)
  end

  def handle_event(
        :info,
        {:timeout, timer, {:admission_timeout, task_ref}},
        :admitting,
        %State{admission_task: %{task: %Task{ref: task_ref} = task, timer: timer}} = data
      ) do
    _result = Task.shutdown(task, :brutal_kill)
    data = %{data | admission_task: nil}

    error =
      Error.timeout_error("Agent Plugin admission timed out",
        timeout: data.directive_timeout,
        details: %{turn_id: data.active.turn_id}
      )

    fail_turn(error, :prepare, data)
  end

  def handle_event(
        :info,
        {ref, result},
        :directing,
        %State{directive_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    Process.demonitor(ref, [:flush])
    cancel_directive_timer(pending.timer)
    data = %{data | directive_task: nil}

    directive_result =
      case result do
        :ok -> {:ok, data}
        {:error, reason} -> {:error, reason, data}
        other -> {:error, {:invalid_plugin_dispatch_result, other}, data}
      end

    complete_directive(directive_result, pending.rest, pending.context, pending.span)
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        :directing,
        %State{directive_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    cancel_directive_timer(pending.timer)
    data = %{data | directive_task: nil}

    error =
      Error.execution_error("Agent Plugin Directive task exited",
        details: %{reason: reason}
      )

    complete_directive({:error, error, data}, pending.rest, pending.context, pending.span, :exit)
  end

  def handle_event(
        :info,
        {:timeout, timer, {:directive_timeout, task_ref}},
        :directing,
        %State{
          directive_task: %{task: %Task{ref: task_ref} = task, timer: timer} = pending
        } = data
      ) do
    _result = Task.shutdown(task, :brutal_kill)
    data = %{data | directive_task: nil}

    error =
      Error.timeout_error("Agent Directive timed out",
        timeout: data.directive_timeout,
        details: %{turn_id: data.active.turn_id}
      )

    complete_directive({:error, error, data}, pending.rest, pending.context, pending.span)
  end

  def handle_event(:info, {:DOWN, ref, :process, pid, reason}, phase, %State{} = data) do
    handle_process_down(ref, pid, reason, phase, data)
  end

  def handle_event(
        :info,
        {:timeout, ref, :agent_idle_timeout},
        :idle,
        %State{idle_timer: ref} = data
      ) do
    {:stop, {:shutdown, :idle_timeout}, %{data | idle_timer: nil}}
  end

  def handle_event(:info, {:timeout, _ref, :agent_idle_timeout}, _phase, %State{}) do
    :keep_state_and_data
  end

  def handle_event(:info, message, :running, %State{active: %ActiveTurn{} = active} = data) do
    case data.exec_module.handle_message(active.exec_handle, message) do
      {:done, result} -> finish_turn(result, data)
      :ignore -> :keep_state_and_data
      {:error, error} -> fail_turn(error, :execute, data)
    end
  end

  def handle_event(:info, _message, phase, %State{})
      when phase in [:idle, :admitting, :directing],
      do: :keep_state_and_data

  def handle_event(:internal, {:handle_directives, [], context}, :directing, %State{} = data) do
    continue_directives([], context, data)
  end

  def handle_event(
        :internal,
        {:handle_directives, [directive | rest], context},
        :directing,
        %State{} = data
      ) do
    handle_one_directive(directive, rest, context, data)
  end

  def handle_event({:call, from}, _request, _phase, %State{}) do
    {:keep_state_and_data, [{:reply, from, {:error, :unknown_call}}]}
  end

  def handle_event(_event_type, _event, _phase, %State{}), do: :keep_state_and_data

  @impl true
  def terminate(reason, _phase, %State{} = data) do
    AgentTelemetry.finish(data.activation_span, AgentTelemetry.result_metadata({:error, reason}))
    metadata = Map.put(AgentTelemetry.lifecycle_metadata(data), :operation, :stop)

    result =
      AgentTelemetry.with_span(:lifecycle, metadata, fn -> terminate_agent(reason, data) end)

    notify_startup(data, {:error, normalize_startup_error(reason)})
    result
  end

  defp terminate_agent(reason, data) do
    if match?(%ActiveTurn{exec_handle: handle} when not is_nil(handle), data.active) do
      try do
        _result = data.exec_module.cancel(data.active.exec_handle)
      catch
        _kind, _reason -> :ok
      end
    end

    stop_plugin_readiness(data.plugin_bootstrap)
    stop_admission_task(data.admission_task)
    stop_directive_task(data.directive_task)

    if data.directive_task do
      finish_span_error(data.directive_task.span, {:agent_stopped, reason})
    end

    AgentTelemetry.interrupted(data, reason)
    cancel_idle_timer(data)
    maybe_persist_on_stop(reason, data)
    maybe_delete_runtime_checkpoint(reason, data)
    retire_remote_spawn(reason, data)
    PluginLifecycle.stop_all(data, :shutdown)
    TraceContext.clear()
    :ok
  end

  defp start_turn(%Signal{} = signal, from, context, %State{} = data) do
    data = cancel_idle_timer(data)
    {_traced_signal, trace} = TraceContext.ensure_from_signal(signal)
    span = start_signal_span(signal, data)
    active = ActiveTurn.new(signal, from, data.state_version, span)
    data = %{data | active: active}
    metadata = data |> AgentTelemetry.turn_metadata() |> Map.merge(trace)

    semantic =
      AgentTelemetry.start(:turn, Map.merge(metadata, %{stage: :evaluate, committed?: false}), %{
        state_version_before: data.state_version
      })

    data = %{data | active: %{active | telemetry_span: semantic}}

    try do
      with {:ok, command} <- initial_command(signal, context, data) do
        if Plugin.admits?(data.plugin_specs) do
          start_admission_task(command, data)
        else
          begin_turn_execution(command, data)
        end
      else
        {:error, reason} -> fail_turn(reason, :prepare, data)
      end
    rescue
      error ->
        finish_span_fault(span, :error, error, __STACKTRACE__)
        AgentTelemetry.settled(data, turn_outcome(data, :failed, :prepare, error), :error)
        TraceContext.clear()
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        finish_span_fault(span, kind, reason, __STACKTRACE__)
        AgentTelemetry.settled(data, turn_outcome(data, :failed, :prepare, reason), kind)
        TraceContext.clear()
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp start_plugin_readiness(%State{} = data) do
    owner = self()
    token = make_ref()

    {pid, ref} =
      spawn_monitor(fn ->
        send(owner, {:plugin_readiness, token, PluginLifecycle.await_all(data)})
      end)

    %{data | plugin_bootstrap: %{pid: pid, ref: ref, token: token}}
  end

  defp stop_plugin_readiness(%{pid: pid, ref: ref}) do
    Process.demonitor(ref, [:flush])
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  defp stop_plugin_readiness(nil), do: :ok

  defp stop_admission_task(%{task: %Task{} = task} = pending) do
    cancel_task_timer(Map.get(pending, :timer))
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp stop_admission_task(nil), do: :ok

  defp stop_directive_task(%{task: %Task{} = task} = pending) do
    cancel_directive_timer(Map.get(pending, :timer))
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp stop_directive_task(nil), do: :ok

  defp initial_command(%Signal{} = signal, context, %State{} = data) do
    context = Map.merge(context, %{jido: data.jido, partition: data.partition})
    Jido.Agent.Command.new(data.agent, signal, context)
  end

  defp start_admission_task(command, %State{} = data) do
    with {:ok, runtime_refs} <-
           plugin_runtime_refs(data, Plugin.admission_modules(data.plugin_specs)) do
      supervisor = Jido.Exec.task_supervisor_name(data.jido)

      task =
        Task.Supervisor.async(supervisor, fn ->
          Plugin.admit(command, data.plugin_specs, runtime_refs)
        end)

      timer = start_task_timer(data.directive_timeout, :admission_timeout, task.ref)
      {:next_state, :admitting, %{data | admission_task: %{task: task, timer: timer}}}
    else
      {:error, reason} -> fail_turn(reason, :prepare, data)
    end
  rescue
    error -> fail_turn(error, :prepare, data)
  catch
    kind, reason -> fail_turn({kind, reason}, :prepare, data)
  end

  defp begin_turn_execution(%Jido.Agent.Command{} = command, %State{} = data) do
    # Admission receives the original Signal. Attach the Turn trace only at
    # the existing execution boundary, after admission has finished.
    signal =
      if Jido.Tracing.Trace.get(command.signal) do
        command.signal
      else
        case Jido.Tracing.Trace.put(command.signal, data.active.telemetry_span.metadata) do
          {:ok, traced} -> traced
          {:error, _} -> command.signal
        end
      end

    {signal, _trace} = TraceContext.ensure_from_signal(signal)
    command = %{command | signal: signal}

    case start_exec(command, data) do
      {:ok, handle, prepared} ->
        active = ActiveTurn.begin_execution(data.active, handle, prepared)
        {:next_state, :running, %{data | active: active}}

      {:error, reason} ->
        fail_turn(reason, :prepare, data)
    end
  end

  defp start_exec(%Jido.Agent.Command{} = command, %State{} = data) do
    exec_opts = Keyword.put(data.exec_opts, :jido, data.jido)
    command_options = Keyword.put(exec_opts, :context, command.context)

    with {:ok, prepared} <-
           Runner.prepare(command.agent, command.signal, command_options, data.plugin_specs),
         {:ok, handle} <- start_async_exec(prepared, data.exec_module),
         :ok <- link_exec(handle) do
      {:ok, handle, prepared}
    end
  end

  defp link_exec(%{pid: pid}) when is_pid(pid) do
    Process.link(pid)
    :ok
  end

  defp link_exec(_handle), do: :ok

  defp start_async_exec(prepared, exec_module) do
    {:ok,
     exec_module.run_async(
       prepared.turn.executable,
       prepared.turn.input,
       prepared.context,
       prepared.exec_opts
     )}
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp finish_turn(result, %State{active: %ActiveTurn{prepared: prepared}} = data) do
    case result do
      {:error, reason} ->
        fail_turn(reason, :execute, data)

      {:error, reason, _extras} ->
        fail_turn(reason, :execute, data)

      _result ->
        case Runner.finish_for_server(prepared, result) do
          {:ok, agent, directives} -> finish_success(agent, directives, data)
          {:error, reason} -> fail_turn(reason, :finalize, data)
        end
    end
  end

  defp finish_success(%Agent{} = agent, directives, %State{} = data) do
    with {:ok, agent} <- Jido.Agent.StateBudget.transition(data.agent, agent),
         {:ok, directives} <- prepare_directives(directives, data) do
      commit_turn(agent, directives, data)
    else
      {:error, reason} -> fail_turn(reason, :finalize, data)
    end
  end

  defp commit_turn(agent, directives, %State{active: %ActiveTurn{} = active} = data) do
    # This is a commit revision, not a count of distinct state values.
    version = data.state_version + 1

    result =
      AgentTelemetry.with_span(
        :commit,
        Map.put(AgentTelemetry.turn_metadata(data), :stage, :commit),
        fn -> persist_commit(data, agent, version) end
      )

    case result do
      :ok -> commit_checkpointed_turn(agent, directives, version, active, data)
      {:error, reason} -> fail_turn({:persistence_failed, reason}, :commit, data)
    end
  end

  defp commit_checkpointed_turn(agent, directives, version, active, data) do
    committed_active = ActiveTurn.mark_committed(active, version, length(directives))
    AgentTelemetry.committed(data, version, length(directives))

    next_data =
      data
      |> Map.merge(%{
        agent: agent,
        state_version: version,
        active: committed_active
      })
      |> record_event(:turn_committed, %{
        turn_id: active.turn_id,
        signal_id: active.effective_signal.id,
        signal_type: active.effective_signal.type,
        state_version: version,
        directive_count: length(directives)
      })

    actions =
      reply_action(active.caller, {:ok, agent}) ++
        directive_actions(directives, agent.id, active)

    phase = if directives == [], do: :idle, else: :directing

    next_data =
      if directives == [] do
        outcome = turn_outcome(next_data, :succeeded, :commit, nil)
        next_data |> complete_outcome(outcome) |> maybe_start_idle_timer(phase)
      else
        maybe_start_idle_timer(next_data, phase)
      end

    finish_span(active.span, %{directive_count: length(directives), state_version: version})
    if phase == :idle, do: TraceContext.clear()
    {:next_state, phase, next_data, actions}
  end

  defp fail_turn(reason, stage, %State{active: %ActiveTurn{} = active} = data) do
    finish_span_error(active.span, reason)
    TraceContext.clear()
    signal = active.effective_signal || active.source_signal
    maybe_log_cast_failure(active.caller, signal, reason, data.agent.id)
    outcome = turn_outcome(data, outcome_status(reason), stage, reason)

    next_data =
      data
      |> Map.update!(:error_count, &(&1 + 1))
      |> complete_outcome(outcome)

    decision =
      case reason do
        {:persistence_failed, failure} ->
          if uncertain_write?(failure),
            do: {:stop, {:shutdown, {:persistence_failed, failure}}, next_data},
            else: error_policy_decision(outcome, next_data)

        _reason ->
          error_policy_decision(outcome, next_data)
      end

    case decision do
      {:continue, policy_data} ->
        {:next_state, :idle, maybe_start_idle_timer(policy_data, :idle),
         reply_action(active.caller, {:error, reason})}

      {:stop, stop_reason, policy_data} ->
        replies = reply_action(active.caller, {:error, reason})
        stop_reason = normalize_stop_reason(stop_reason)

        if replies == [] do
          {:stop, stop_reason, policy_data}
        else
          {:stop_and_reply, stop_reason, replies, policy_data}
        end
    end
  end

  defp uncertain_write?(:indeterminate), do: true
  defp uncertain_write?({:indeterminate, _reason}), do: true

  defp uncertain_write?(%Error.ExecutionError{details: %{operation: :compare_and_swap}}),
    do: true

  defp uncertain_write?(_reason), do: false

  defp cancel_active(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    case data.exec_module.cancel(active.exec_handle) do
      :ok ->
        finish_span_error(active.span, :cancelled)
        TraceContext.clear()
        outcome = turn_outcome(data, :cancelled, :execute, :cancelled)
        next_data = data |> complete_outcome(outcome) |> maybe_start_idle_timer(:idle)

        actions =
          reply_action(active.caller, {:error, :cancelled}) ++ [{:reply, cancel_from, :ok}]

        {:next_state, :idle, next_data, actions}

      {:error, error} ->
        finish_span_error(active.span, error)
        TraceContext.clear()
        outcome = turn_outcome(data, :indeterminate, :execute, error)
        next_data = complete_outcome(data, outcome)

        actions =
          reply_action(active.caller, {:error, error}) ++
            [{:reply, cancel_from, {:error, error}}]

        {:stop_and_reply, {:shutdown, {:exec_cancellation_failed, error}}, actions, next_data}
    end
  end

  defp cancel_admission(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    stop_admission_task(data.admission_task)
    finish_span_error(active.span, :cancelled)
    TraceContext.clear()
    outcome = turn_outcome(data, :cancelled, :prepare, :cancelled)

    next_data =
      data
      |> Map.put(:admission_task, nil)
      |> complete_outcome(outcome)
      |> maybe_start_idle_timer(:idle)

    actions = reply_action(active.caller, {:error, :cancelled}) ++ [{:reply, cancel_from, :ok}]
    {:next_state, :idle, next_data, actions}
  end

  defp prepare_directives(directives, %State{} = data) do
    with :ok <- ensure_directive_limit(directives, data.max_directives_per_turn),
         :ok <- ensure_terminal_directive_last(directives) do
      {:ok, directives}
    end
  end

  defp handle_one_directive(directive, rest, context, data) do
    span = start_directive_span(directive, context, data)

    if DirectiveRuntime.signal_directive?(directive) do
      start_signal_directive(directive, rest, context, span, data)
    else
      handle_directive(directive, rest, context, span, data)
    end
  end

  defp start_signal_directive(
         directive,
         rest,
         context,
         span,
         %State{active: %ActiveTurn{} = active} = data
       ) do
    modules = Plugin.dispatch_modules(data.plugin_specs)

    with {:ok, prepared_directive, target} <-
           DirectiveRuntime.prepare_signal(directive, context, data),
         {:ok, runtime_refs} <- plugin_runtime_refs(data, modules) do
      plugin_context = %PluginSignalContext{
        turn_id: active.turn_id,
        agent_id: data.agent.id,
        source_signal: active.source_signal,
        effective_signal: active.effective_signal,
        turn_context: active.turn_context,
        target: target,
        state_version: data.state_version,
        plugin_state: nil,
        jido: data.jido,
        partition: data.partition
      }

      agent_server = self()

      start_directive_task(
        fn ->
          with {:ok, signal} <-
                 Plugin.prepare_dispatch(
                   prepared_directive.signal,
                   data.plugin_specs,
                   runtime_refs,
                   plugin_context,
                   data.agent.state
                 ) do
            prepared_directive
            |> Map.put(:signal, signal)
            |> DirectiveRuntime.dispatch_prepared(data, agent_server)
          end
        end,
        rest,
        context,
        span,
        data
      )
    else
      {:error, reason} -> complete_directive({:error, reason, data}, rest, context, span)
    end
  end

  defp handle_directive(directive, rest, context, span, data) do
    if Directive.built_in?(directive) do
      directive
      |> DirectiveRuntime.handle(context, data)
      |> complete_directive(rest, context, span)
    else
      start_plugin_directive(directive, rest, context, span, data)
    end
  end

  defp complete_directive(result, rest, context, span, fault_kind \\ nil) do
    case result do
      {:ok, next_data} ->
        finish_span(span, %{result: :ok})
        active = ActiveTurn.mark_directive_completed(next_data.active)
        continue_directives(rest, context, %{next_data | active: active})

      {:error, reason, next_data} ->
        if fault_kind,
          do: finish_span_fault(span, fault_kind, reason, []),
          else: finish_span_error(span, reason)

        Logger.error("Agent Directive handling failed",
          agent_id: context.agent_id,
          signal_type: context.signal.type,
          reason: inspect(reason)
        )

        active = ActiveTurn.mark_directive_failed(next_data.active)

        next_data =
          next_data
          |> Map.put(:active, active)
          |> record_event(:directive_failed, %{
            turn_id: active.turn_id,
            reason: reason
          })

        outcome = turn_outcome(next_data, outcome_status(reason), :directive, reason)
        next_data = complete_outcome(next_data, outcome)

        apply_directive_error_policy(outcome, next_data)

      {:stop, reason, next_data} ->
        finish_span(span, %{result: :stop})
        active = ActiveTurn.mark_directive_completed(next_data.active)
        next_data = %{next_data | active: active}
        outcome = turn_outcome(next_data, :succeeded, :directive, nil)
        {:stop, normalize_stop_reason(reason), complete_outcome(next_data, outcome)}
    end
  end

  defp start_plugin_directive(directive, rest, context, span, %State{} = data) do
    case Plugin.directive_owner(data.plugin_specs, directive) do
      %Jido.Plugin.Spec{dispatch?: false} ->
        complete_directive({:ok, data}, rest, context, span)

      %Jido.Plugin.Spec{} = plugin ->
        dispatch_plugin_directive(plugin, directive, rest, context, span, data)

      nil ->
        complete_directive(
          {:error, {:unsupported_agent_directive, directive}, data},
          rest,
          context,
          span
        )
    end
  end

  defp dispatch_plugin_directive(
         plugin,
         directive,
         rest,
         context,
         span,
         %State{active: %ActiveTurn{} = active} = data
       ) do
    plugin_context = %PluginDirectiveContext{
      turn_id: active.turn_id,
      agent_id: data.agent.id,
      source_signal: context.source_signal,
      effective_signal: context.signal,
      state_version: data.state_version,
      plugin_state: plugin_state_value(data.agent.state, plugin.state_key),
      turn_context: context.turn_context,
      jido: data.jido,
      partition: data.partition
    }

    # A restarting Plugin can need Agent state to become ready. Resolve its
    # reference in the bounded task so the Agent can answer that state query.
    start_directive_task(
      fn ->
        with {:ok, runtime_ref} <- plugin_runtime_ref(data, plugin) do
          Plugin.dispatch(plugin, runtime_ref, directive, plugin_context)
        end
      end,
      rest,
      context,
      span,
      data
    )
  end

  defp start_directive_task(fun, rest, context, span, data) do
    supervisor = Jido.Exec.task_supervisor_name(data.jido)
    task = Task.Supervisor.async(supervisor, fun)
    timer = start_directive_timer(data.directive_timeout, task.ref)
    pending = %{task: task, timer: timer, rest: rest, context: context, span: span}
    {:keep_state, %{data | directive_task: pending}}
  rescue
    error -> complete_directive({:error, error, data}, rest, context, span)
  catch
    kind, reason -> complete_directive({:error, {kind, reason}, data}, rest, context, span)
  end

  defp start_directive_timer(timeout, task_ref) do
    start_task_timer(timeout, :directive_timeout, task_ref)
  end

  defp start_task_timer(:infinity, _tag, _task_ref), do: nil

  defp start_task_timer(timeout, tag, task_ref) do
    :erlang.start_timer(timeout, self(), {tag, task_ref})
  end

  defp cancel_directive_timer(timer), do: cancel_task_timer(timer)

  defp cancel_task_timer(nil), do: :ok

  defp cancel_task_timer(timer) do
    _result = :erlang.cancel_timer(timer)
    :ok
  end

  defp plugin_state_value(_state, nil), do: nil
  defp plugin_state_value(state, key), do: Map.get(state, key)

  defp continue_directives([], _context, %State{active: %ActiveTurn{}} = data) do
    TraceContext.clear()
    outcome = turn_outcome(data, :succeeded, :directive, nil)
    next_data = data |> complete_outcome(outcome) |> maybe_start_idle_timer(:idle)
    {:next_state, :idle, next_data}
  end

  defp continue_directives(rest, context, data) do
    {:keep_state, data, [{:next_event, :internal, {:handle_directives, rest, context}}]}
  end

  defp directive_actions([], _agent_id, _active), do: []

  defp directive_actions(directives, agent_id, %ActiveTurn{} = active) do
    context = %DirectiveContext{
      turn_id: active.turn_id,
      agent_id: agent_id,
      source_signal: active.source_signal,
      signal: active.effective_signal,
      turn_context: active.turn_context
    }

    [{:next_event, :internal, {:handle_directives, directives, context}}]
  end

  defp public_status(phase, %State{} = data) do
    message_queue_len =
      case Process.info(self(), :message_queue_len) do
        {:message_queue_len, length} -> length
        nil -> 0
      end

    %{
      phase: phase,
      agent_id: data.agent.id,
      state_version: data.state_version,
      admission: %{
        postponed: MapSet.size(data.postponed_tokens),
        limit: data.max_postponed_signals,
        message_queue_len: message_queue_len
      },
      runtime: %{
        partition: data.partition,
        parent: public_parent(data.parent),
        child_count: map_size(data.children),
        pending_child_spawns: pending_child_spawns(data),
        error_count: data.error_count,
        lifecycle: %{
          pool: data.pool,
          attached: map_size(data.attachments),
          idle_timeout: data.idle_timeout,
          idle_timer?: not is_nil(data.idle_timer)
        }
      },
      active: public_active(data.active)
    }
  end

  defp public_active(nil), do: nil

  defp public_active(%ActiveTurn{} = active) do
    signal = active.effective_signal || active.source_signal

    %{
      turn_id: active.turn_id,
      source_signal_id: active.source_signal.id,
      signal_id: signal.id,
      signal_type: signal.type,
      start_version: active.start_version,
      committed_version: active.committed_version
    }
  end

  defp postpone_call(from, token, _signal, deadline, %State{} = data) do
    cond do
      admission_expired?(deadline) ->
        {:keep_state, forget_postponed(data, token),
         [{:reply, from, {:error, :admission_timeout}}]}

      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      admission_full?(data) ->
        {:keep_state_and_data, [{:reply, from, {:error, overload_error(data)}}]}

      true ->
        {:keep_state, remember_postponed(data, token), [:postpone]}
    end
  end

  defp postpone_cast(token, signal, %State{} = data) do
    cond do
      MapSet.member?(data.postponed_tokens, token) ->
        {:keep_state_and_data, [:postpone]}

      admission_full?(data) ->
        Logger.warning("Agent Signal cast dropped because the Server is overloaded",
          agent_id: data.agent.id,
          signal_id: signal.id,
          signal_type: signal.type
        )

        :keep_state_and_data

      true ->
        {:keep_state, remember_postponed(data, token), [:postpone]}
    end
  end

  defp remember_postponed(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.put(data.postponed_tokens, token)}
  end

  defp forget_postponed(%State{} = data, token) do
    %{data | postponed_tokens: MapSet.delete(data.postponed_tokens, token)}
  end

  defp admission_full?(%State{max_postponed_signals: :infinity}), do: false

  defp admission_full?(%State{} = data) do
    MapSet.size(data.postponed_tokens) >= data.max_postponed_signals
  end

  defp overload_error(%State{} = data) do
    {:overloaded,
     %{limit: data.max_postponed_signals, postponed: MapSet.size(data.postponed_tokens)}}
  end

  defp reentrant_turn_call?({caller, _tag}, %ActiveTurn{exec_handle: %{pid: root}})
       when is_pid(caller) and is_pid(root) do
    related_exec_process?(caller, root, %{}, 0)
  end

  defp reentrant_turn_call?(_from, _active), do: false

  defp reentrant_admission_call?({caller, _tag}, %{task: %Task{pid: root}})
       when is_pid(caller) and is_pid(root) do
    related_exec_process?(caller, root, %{}, 0)
  end

  defp reentrant_admission_call?(_from, _admission_task), do: false

  defp reentrant_directive_call?({caller, _tag}, %{task: %Task{pid: root}})
       when is_pid(caller) and is_pid(root) do
    related_exec_process?(caller, root, %{}, 0)
  end

  defp reentrant_directive_call?(_from, _directive_task), do: false

  defp plugin_runtime_refs(%State{} = data, modules) do
    Enum.reduce_while(modules, {:ok, %{}}, fn module, {:ok, refs} ->
      spec = Enum.find(data.plugin_specs, &(&1.module == module))

      case plugin_runtime_ref(data, spec) do
        {:ok, runtime_ref} -> {:cont, {:ok, Map.put(refs, module, runtime_ref)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp plugin_runtime_ref(_data, %Jido.Plugin.Spec{runtime?: false}), do: {:ok, nil}

  defp plugin_runtime_ref(data, %Jido.Plugin.Spec{module: module}) do
    PluginLifecycle.runtime_ref(data, module)
  end

  defp related_exec_process?(pid, root, _visited, _depth) when pid == root, do: true
  defp related_exec_process?(_pid, _root, _visited, depth) when depth >= 8, do: false

  defp related_exec_process?(pid, root, visited, depth) do
    if Map.has_key?(visited, pid) do
      false
    else
      visited = Map.put(visited, pid, true)

      pid
      |> exec_process_parents()
      |> Enum.any?(&related_exec_process?(&1, root, visited, depth + 1))
    end
  end

  defp exec_process_parents(pid) when node(pid) != node(), do: []

  defp exec_process_parents(pid) do
    monitored_by =
      case Process.info(pid, :monitored_by) do
        {:monitored_by, pids} -> pids
        nil -> []
      end

    callers =
      case Process.info(pid, :dictionary) do
        {:dictionary, dictionary} ->
          dictionary
          |> Keyword.get(:"$callers", [])
          |> List.wrap()

        nil ->
          []
      end

    (monitored_by ++ callers)
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  defp ensure_directive_limit(_directives, :infinity), do: :ok

  defp ensure_directive_limit(directives, limit) when length(directives) <= limit, do: :ok

  defp ensure_directive_limit(directives, limit) do
    {:error, {:too_many_directives, %{count: length(directives), limit: limit}}}
  end

  defp ensure_terminal_directive_last(directives) do
    case Enum.find_index(directives, &match?(%Directive.Stop{}, &1)) do
      nil -> :ok
      index when index == length(directives) - 1 -> :ok
      index -> {:error, {:terminal_directive_not_last, %{index: index}}}
    end
  end

  defp validate_exec_module(module) when is_atom(module) do
    required = [run_async: 4, handle_message: 2, cancel: 1]

    with {:module, ^module} <- Code.ensure_loaded(module),
         true <-
           Enum.all?(required, fn {name, arity} -> function_exported?(module, name, arity) end) do
      {:ok, module}
    else
      _reason ->
        {:error,
         Error.validation_error("Agent Server Exec module has an invalid contract",
           kind: :config,
           details: %{module: module}
         )}
    end
  end

  defp validate_exec_module(module) do
    {:error,
     Error.validation_error("Agent Server Exec module must be a module",
       kind: :config,
       details: %{module: module}
     )}
  end

  defp validate_keyword(value, _field) when is_list(value) and value == [], do: {:ok, value}

  defp validate_keyword(value, field) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, Error.validation_error("#{field} must be a keyword list", field: field)}
    end
  end

  defp validate_keyword(_value, field) do
    {:error, Error.validation_error("#{field} must be a keyword list", field: field)}
  end

  defp validate_limit(:infinity, _field), do: {:ok, :infinity}
  defp validate_limit(value, _field) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_limit(value, field) do
    {:error,
     Error.validation_error("#{field} must be :infinity or a non-negative integer",
       field: field,
       details: %{value: value}
     )}
  end

  defp maybe_log_cast_failure(nil, signal, reason, agent_id) do
    Logger.error("Agent Signal cast failed",
      agent_id: agent_id,
      signal_id: signal.id,
      signal_type: signal.type,
      reason: inspect(reason)
    )
  end

  defp maybe_log_cast_failure(_from, _signal, _reason, _agent_id), do: :ok

  defp handle_process_down(ref, pid, reason, phase, %State{} = data) do
    case Map.fetch(data.attachments, pid) do
      {:ok, ^ref} ->
        next_data =
          data
          |> remove_attachment(pid)
          |> maybe_start_idle_timer(phase)

        {:keep_state, next_data}

      _other ->
        cond do
          match?(%ParentRef{ref: ^ref, pid: ^pid}, data.parent) ->
            handle_parent_down(reason, data)

          child_entry = State.child_by_ref(data, ref) ->
            handle_child_down(child_entry, pid, reason, data)

          phase == :running and match?(%ActiveTurn{}, data.active) ->
            handle_exec_message({:DOWN, ref, :process, pid, reason}, data)

          true ->
            :keep_state_and_data
        end
    end
  end

  defp handle_exec_message(message, %State{active: %ActiveTurn{} = active} = data) do
    case data.exec_module.handle_message(active.exec_handle, message) do
      {:done, result} -> finish_turn(result, data)
      :ignore -> :keep_state_and_data
      {:error, error} -> fail_turn(error, :execute, data)
    end
  end

  defp handle_child_down({key, %ChildInfo{kind: :plugin} = child}, pid, reason, data) do
    next_data = State.remove_child(data, key)
    {:stop, {:plugin_runtime_down, child.module, pid, reason}, next_data}
  end

  defp handle_child_down({key, %ChildInfo{} = child}, pid, reason, data) do
    next_data = State.remove_child(data, key)

    next_data =
      if clean_child_exit?(reason) do
        _ = delete_child_relationship(data, child)
        %{next_data | child_spawn_requests: Map.delete(next_data.child_spawn_requests, key)}
      else
        next_data
      end

    signal =
      ChildExit.new!(
        %{tag: child.tag, child_id: child.id, pid: pid, reason: reason},
        source: "/agent/#{data.agent.id}"
      )

    cast(self(), signal)
    {:keep_state, next_data}
  end

  defp clean_child_exit?(:normal), do: true
  defp clean_child_exit?(:shutdown), do: true
  defp clean_child_exit?({:shutdown, _reason}), do: true
  defp clean_child_exit?(_reason), do: false

  defp handle_parent_down(reason, %State{parent: %ParentRef{} = parent} = data) do
    next_data = %{data | parent: nil, orphaned_from: parent}
    _ = delete_own_relationship(next_data)

    case data.on_parent_death do
      :stop ->
        next_data = cancel_active_for_parent(next_data)
        {:stop, {:shutdown, {:parent_down, reason}}, next_data}

      :continue ->
        {:keep_state, next_data}

      :emit_orphan ->
        signal =
          Orphaned.new!(
            %{
              parent_id: parent.id,
              parent_pid: parent.pid,
              tag: parent.tag,
              meta: parent.meta,
              reason: reason
            },
            source: "/agent/#{data.agent.id}"
          )

        cast(self(), signal)
        {:keep_state, next_data}
    end
  end

  defp cancel_active_for_parent(%State{active: %ActiveTurn{exec_handle: handle} = active} = data)
       when not is_nil(handle) do
    {status, error} =
      case data.exec_module.cancel(handle) do
        :ok -> {:cancelled, {:parent_down, :cancelled}}
        {:error, reason} -> {:indeterminate, {:parent_down, {:cancellation_failed, reason}}}
      end

    finish_span_error(active.span, error)
    TraceContext.clear()
    outcome = turn_outcome(data, status, :execute, error)
    if active.caller, do: :gen_statem.reply(active.caller, {:error, {:parent_down, :cancelled}})
    complete_outcome(data, outcome)
  catch
    _kind, _reason ->
      finish_span_error(active.span, {:parent_down, :cancelled})
      TraceContext.clear()
      outcome = turn_outcome(data, :indeterminate, :execute, {:parent_down, :cancelled})
      complete_outcome(data, outcome)
  end

  defp cancel_active_for_parent(data), do: data

  defp attach_parent(%State{parent: %ParentRef{}}, _parent), do: {:error, :already_has_parent}

  defp attach_parent(%State{} = data, %ParentRef{pid: pid} = parent) do
    cond do
      pid == self() ->
        {:error, :cannot_adopt_self}

      not is_pid(pid) or not Process.alive?(pid) ->
        {:error, :parent_not_alive}

      true ->
        monitored = %{parent | ref: Process.monitor(pid)}
        next_data = %{data | parent: monitored, orphaned_from: nil}

        case persist_own_relationship(next_data) do
          :ok ->
            {:ok, next_data}

          {:error, reason} ->
            Process.demonitor(monitored.ref, [:flush])
            {:error, {:relationship_persist_failed, reason}}
        end
    end
  end

  defp monitor_parent(nil), do: nil

  defp monitor_parent(%ParentRef{pid: pid} = parent) when is_pid(pid) do
    %{parent | ref: Process.monitor(pid)}
  end

  defp restore_parent(%Options{parent: %ParentRef{} = parent}, _agent), do: parent

  defp restore_parent(%Options{jido: jido, partition: partition}, agent)
       when is_atom(jido) and not is_nil(jido) do
    with {:ok, binding} <- Jido.agent_parent_binding(jido, agent.id, partition: partition),
         parent_pid when is_pid(parent_pid) <-
           whereis(Jido.registry_name(jido), binding.parent_id,
             partition: binding.parent_partition
           ),
         true <- Process.alive?(parent_pid),
         {:ok, parent} <-
           ParentRef.new(%{
             pid: parent_pid,
             id: binding.parent_id,
             partition: binding.parent_partition,
             tag: binding.tag,
             creation_cause: Map.get(binding, :creation_cause),
             meta: binding.meta
           }) do
      parent
    else
      _reason -> nil
    end
  end

  defp restore_parent(%Options{}, _agent), do: nil

  defp notify_parent_online(%State{parent: %ParentRef{} = parent} = data) do
    send(
      parent.pid,
      {:agent_child_online, self(), data.agent.id, data.agent.module, data.partition, parent.tag,
       parent.meta}
    )

    :ok
  end

  defp notify_parent_online(%State{}), do: :ok

  defp verify_child_online(pid, child_id, tag, %State{} = data) do
    case creation_info(pid) do
      {:ok,
       %{agent_id: ^child_id, parent: %ParentRef{pid: owner, id: parent_id, tag: ^tag} = parent} =
           info}
      when owner == self() and parent_id == data.agent.id ->
        with :ok <- verify_child_placement(pid, tag, parent, data), do: {:ok, info}

      _other ->
        {:error, :parent_mismatch}
    end
  end

  defp verify_child_placement(pid, tag, parent, data) do
    case Map.get(data.child_spawn_requests, tag) do
      %{request_id: request, directive: %{node: target}} ->
        if node(pid) == target and parent.spawn_ref == request,
          do: :ok,
          else: {:error, :spawn_request_mismatch}

      nil when node(pid) == node() ->
        :ok

      nil ->
        {:error, :unknown_remote_child}
    end
  end

  defp pending_child_spawns(data) do
    for {tag, %{status: :pending} = request} <- data.child_spawn_requests, into: %{} do
      {tag, %{node: request.directive.node, request_id: request.request_id}}
    end
  end

  defp track_online_child(data, pid, info) do
    tag = info.parent.tag
    meta = info.parent.meta

    data =
      case Map.fetch(data.child_spawn_requests, tag) do
        {:ok, request} ->
          %{
            data
            | child_spawn_requests:
                Map.put(data.child_spawn_requests, tag, %{request | status: :active})
          }

        :error ->
          data
      end

    case State.child(data, tag) do
      %ChildInfo{pid: ^pid} ->
        data

      existing ->
        if match?(%ChildInfo{}, existing), do: Process.demonitor(existing.ref, [:flush])

        child =
          ChildInfo.new!(
            pid: pid,
            ref: Process.monitor(pid),
            module: info.agent_module,
            id: info.agent_id,
            activation_id: info.activation_id,
            creation_cause: info.parent.creation_cause,
            partition: info.partition,
            tag: tag,
            kind: :agent,
            meta: meta
          )

        _ = persist_child_relationship(data, child)

        signal =
          Jido.AgentServer.Signal.ChildStarted.for_child(
            data.agent.id,
            child,
            not is_nil(existing)
          )

        cast(self(), signal)
        State.add_child(data, tag, child)
    end
  end

  defp relationship_info(%State{} = data) do
    %{
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      partition: data.partition,
      parent: public_parent(data.parent)
    }
  end

  defp directive_context(%State{} = data) do
    signal = Signal.new!(type: "jido.agent.runtime", source: "/agent/#{data.agent.id}", data: %{})

    %DirectiveContext{
      agent_id: data.agent.id,
      source_signal: signal,
      signal: signal
    }
  end

  defp public_child(%ChildInfo{} = child), do: public_child_map(child)

  defp public_child_map(%ChildInfo{} = child) do
    %{
      pid: child.pid,
      module: child.module,
      id: child.id,
      partition: child.partition,
      tag: child.tag,
      kind: child.kind,
      meta: child.meta
    }
  end

  defp public_parent(nil), do: nil

  defp public_parent(%ParentRef{} = parent) do
    %{
      pid: parent.pid,
      id: parent.id,
      partition: parent.partition,
      tag: parent.tag,
      spawn_ref: parent.spawn_ref,
      meta: parent.meta
    }
  end

  defp apply_directive_error_policy(%Outcome{} = outcome, data) do
    next_data = %{data | error_count: data.error_count + 1}

    case error_policy_decision(outcome, next_data) do
      {:continue, policy_data} ->
        TraceContext.clear()
        {:next_state, :idle, maybe_start_idle_timer(policy_data, :idle)}

      {:stop, stop_reason, policy_data} ->
        {:stop, {:shutdown, stop_reason}, policy_data}
    end
  end

  defp error_policy_decision(%Outcome{}, %State{error_policy: :log_only} = data),
    do: {:continue, data}

  defp error_policy_decision(%Outcome{} = outcome, %State{error_policy: :stop_on_error} = data),
    do: {:stop, {:agent_error, outcome.error}, data}

  defp error_policy_decision(
         %Outcome{} = outcome,
         %State{error_policy: {:max_errors, max}} = data
       ) do
    if data.error_count >= max,
      do: {:stop, {:max_agent_errors, outcome.error}, data},
      else: {:continue, data}
  end

  defp error_policy_decision(
         %Outcome{} = outcome,
         %State{error_policy: {:emit_signal, dispatch}} = data
       ) do
    source_signal = outcome.effective_signal || outcome.source_signal

    if source_signal.type != "jido.agent.error" do
      signal =
        Signal.new!(
          type: "jido.agent.error",
          source: "/agent/#{data.agent.id}",
          data: %{
            agent_id: data.agent.id,
            turn_id: outcome.id,
            status: outcome.status,
            stage: outcome.stage,
            committed?: outcome.committed?,
            error: Error.to_map(outcome.error)
          }
        )

      context = directive_context(data)

      _ =
        DirectiveRuntime.handle(
          %Directive.Emit{signal: signal, dispatch: dispatch},
          context,
          data
        )
    end

    {:continue, data}
  end

  defp error_policy_decision(%Outcome{} = outcome, %State{error_policy: policy} = data)
       when is_function(policy, 2) do
    case policy.(outcome.error, outcome) do
      :continue -> {:continue, data}
      {:stop, stop_reason} -> {:stop, stop_reason, data}
      other -> {:stop, {:invalid_error_policy_result, other}, data}
    end
  rescue
    error -> {:stop, {:error_policy_failed, error}, data}
  end

  defp turn_outcome(%State{active: active, agent: agent}, status, stage, error),
    do: ActiveTurn.outcome(active, agent.id, status, stage, error)

  defp complete_outcome(%State{} = data, %Outcome{} = outcome) do
    AgentTelemetry.settled(data, outcome)
    signal = outcome.effective_signal || outcome.source_signal
    event = if outcome.status == :succeeded, do: :turn_completed, else: :turn_failed

    data
    |> Map.put(:active, nil)
    |> then(fn data ->
      if outcome.status == :succeeded, do: %{data | error_count: 0}, else: data
    end)
    |> record_event(event, %{
      turn_id: outcome.id,
      signal_id: signal.id,
      signal_type: signal.type,
      stage: outcome.stage,
      reason: outcome.error,
      outcome: outcome
    })
  end

  defp outcome_status({:child_spawn_indeterminate, _tag, _node, _request, _reason}),
    do: :indeterminate

  defp outcome_status(reason) do
    case Error.to_map(reason) do
      %{type: :timeout} -> :timed_out
      _error -> :failed
    end
  end

  defp record_event(%State{debug: false} = data, _event, _metadata), do: data

  defp record_event(%State{} = data, event, metadata) do
    entry = %{event: event, at: System.system_time(:millisecond), metadata: metadata}
    events = Enum.take([entry | data.debug_events], data.debug_max_events)
    %{data | debug_events: events}
  end

  defp start_signal_span(signal, data) do
    safe_start_span([:jido, :agent_server, :signal], %{
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      signal_type: signal.type,
      jido_instance: data.jido,
      jido_partition: data.partition
    })
  end

  defp start_directive_span(directive, context, data) do
    legacy =
      safe_start_span([:jido, :agent_server, :directive], %{
        agent_id: context.agent_id,
        agent_module: data.agent.module,
        signal_type: context.signal.type,
        directive_type: directive_type(directive),
        jido_instance: data.jido,
        jido_partition: data.partition
      })

    metadata =
      Map.merge(AgentTelemetry.turn_metadata(data), %{
        directive_module: Map.get(directive, :__struct__),
        stage: :directive,
        committed?: true
      })

    telemetry =
      AgentTelemetry.start(:directive, metadata, %{
        directive_index: data.active.directive_completed_count
      })

    %{legacy: legacy, telemetry: telemetry}
  end

  defp safe_start_span(prefix, metadata) do
    Observe.start_span(prefix, metadata)
  rescue
    _error -> nil
  catch
    _kind, _reason -> nil
  end

  defp finish_span(nil, _measurements), do: :ok

  defp finish_span(%{legacy: legacy, telemetry: telemetry}, measurements) do
    finish_span(legacy, measurements)
    AgentTelemetry.finish(telemetry, %{status: :ok})
  end

  defp finish_span(span, measurements) do
    Observe.finish_span(span, measurements)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp finish_span_error(nil, _reason), do: :ok

  defp finish_span_error(%{legacy: legacy, telemetry: telemetry}, reason) do
    finish_span_error(legacy, reason)
    AgentTelemetry.finish(telemetry, AgentTelemetry.result_metadata({:error, reason}))
  end

  defp finish_span_error(span, reason) do
    Observe.finish_span_error(span, :error, reason, [])
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp finish_span_fault(nil, _kind, _reason, _stacktrace), do: :ok

  defp finish_span_fault(%{legacy: legacy, telemetry: telemetry}, kind, reason, stacktrace) do
    finish_span_fault(legacy, kind, reason, stacktrace)
    metadata = AgentTelemetry.result_metadata({:error, reason}) |> Map.put(:kind, kind)
    AgentTelemetry.finish(telemetry, metadata, %{}, :exception)
  end

  defp finish_span_fault(span, kind, reason, stacktrace) do
    Observe.finish_span_error(span, kind, reason, stacktrace)
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp directive_type(%{__struct__: module}), do: module |> Module.split() |> List.last()
  defp directive_type(_directive), do: "Custom"

  defp normalize_event_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp normalize_event_limit(_limit), do: 0

  defp persist_own_relationship(%State{jido: jido, parent: %ParentRef{} = parent} = data)
       when is_atom(jido) and not is_nil(jido) do
    Jido.RuntimeStore.put(
      jido,
      :agent_relationships,
      Jido.partition_key(data.agent.id, data.partition),
      %{
        parent_id: parent.id,
        parent_partition: parent.partition,
        tag: parent.tag,
        creation_cause: parent.creation_cause,
        meta: parent.meta
      }
    )
  end

  defp persist_own_relationship(_data), do: :ok

  defp persist_child_relationship(%State{jido: jido} = data, %ChildInfo{} = child)
       when is_atom(jido) and not is_nil(jido) do
    Jido.RuntimeStore.put(
      jido,
      :agent_relationships,
      Jido.partition_key(child.id, child.partition),
      %{
        parent_id: data.agent.id,
        parent_partition: data.partition,
        tag: child.tag,
        creation_cause: child.creation_cause,
        meta: child.meta
      }
    )
  end

  defp persist_child_relationship(%State{}, %ChildInfo{}), do: :ok

  defp delete_own_relationship(%State{jido: jido} = data)
       when is_atom(jido) and not is_nil(jido) do
    Jido.RuntimeStore.delete(
      jido,
      :agent_relationships,
      Jido.partition_key(data.agent.id, data.partition)
    )
  end

  defp delete_own_relationship(_data), do: :ok

  defp delete_child_relationship(%State{jido: jido}, child)
       when is_atom(jido) and not is_nil(jido) do
    Jido.RuntimeStore.delete(
      jido,
      :agent_relationships,
      Jido.partition_key(child.id, child.partition)
    )
  end

  defp delete_child_relationship(_data, _child), do: :ok

  defp attach_owner(%State{} = data, owner_pid) do
    cond do
      owner_pid == self() ->
        {:error, :cannot_attach_self}

      not Process.alive?(owner_pid) ->
        {:error, :owner_not_alive}

      Map.has_key?(data.attachments, owner_pid) ->
        {:ok, cancel_idle_timer(data)}

      true ->
        ref = Process.monitor(owner_pid)

        {:ok,
         %{
           cancel_idle_timer(data)
           | attachments: Map.put(data.attachments, owner_pid, ref)
         }}
    end
  end

  defp detach_owner(%State{} = data, owner_pid) do
    case Map.fetch(data.attachments, owner_pid) do
      {:ok, ref} ->
        Process.demonitor(ref, [:flush])
        remove_attachment(data, owner_pid)

      :error ->
        data
    end
  end

  defp remove_attachment(%State{} = data, owner_pid) do
    %{data | attachments: Map.delete(data.attachments, owner_pid)}
  end

  defp maybe_start_idle_timer(%State{} = data, phase) when phase != :idle, do: data

  defp maybe_start_idle_timer(%State{idle_timeout: :infinity} = data, :idle), do: data

  defp maybe_start_idle_timer(%State{idle_timer: timer} = data, :idle)
       when not is_nil(timer),
       do: data

  defp maybe_start_idle_timer(%State{} = data, :idle) do
    if map_size(data.attachments) == 0 do
      timer = :erlang.start_timer(data.idle_timeout, self(), :agent_idle_timeout)
      %{data | idle_timer: timer}
    else
      data
    end
  end

  defp cancel_idle_timer(%State{idle_timer: nil} = data), do: data

  defp cancel_idle_timer(%State{idle_timer: timer} = data) do
    _ = :erlang.cancel_timer(timer)
    %{data | idle_timer: nil}
  end

  defp restore_initial_agent(%Options{restore: false} = opts) do
    {:ok, opts.agent, opts.state_version}
  end

  defp restore_initial_agent(%Options{persistence: nil, restore: :required}) do
    {:error, :persistence_not_configured}
  end

  defp restore_initial_agent(%Options{persistence: nil} = opts) do
    {agent, version} = RuntimeCheckpoint.restore(opts)
    {:ok, agent, version}
  end

  defp restore_initial_agent(%Options{} = opts) do
    load_opts = [instance: opts.jido, partition: opts.partition]

    case Jido.Persistence.load_agent_with_revision(
           opts.persistence,
           opts.agent.module,
           opts.agent.id,
           load_opts
         ) do
      {:ok, agent, version} ->
        {:ok, agent, version}

      {:error, :not_found} when opts.restore == :if_found ->
        {:ok, opts.agent, opts.state_version}

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_commit(%State{persistence: nil} = data, agent, version) do
    RuntimeCheckpoint.put(data, agent, version)
  end

  defp persist_commit(%State{} = data, agent, version) do
    persist_agent(data, agent, version, :commit)
  end

  defp persist_agent(data, agent, version, reason, extra_opts \\ [])

  defp persist_agent(%State{persistence: nil}, %Agent{}, _version, _reason, _extra_opts),
    do: {:error, :persistence_not_configured}

  defp persist_agent(%State{} = data, %Agent{} = agent, version, reason, extra_opts) do
    opts =
      extra_opts
      |> Keyword.put(:instance, data.jido)
      |> Keyword.put(:partition, data.partition)
      |> Keyword.put(:revision, version)
      |> Keyword.put(:expected_revision, data.state_version)
      |> Keyword.put(:reason, reason)

    Jido.Persistence.save_agent(data.persistence, agent, opts)
  end

  defp maybe_persist_on_stop({:shutdown, :hibernate}, %State{}), do: :ok
  defp maybe_persist_on_stop({:shutdown, {:persistence_failed, _reason}}, %State{}), do: :ok

  defp maybe_persist_on_stop(reason, %State{persistence: persistence} = data)
       when not is_nil(persistence) do
    if clean_shutdown?(reason) do
      case persist_agent(data, data.agent, data.state_version, :stop) do
        :ok ->
          :ok

        {:error, error} ->
          Logger.error("Agent persistence failed during shutdown",
            agent_id: data.agent.id,
            pool: data.pool,
            reason: inspect(error)
          )
      end
    end
  end

  defp maybe_persist_on_stop(_reason, %State{}), do: :ok

  defp maybe_delete_runtime_checkpoint(reason, %State{} = data) do
    if clean_shutdown?(reason), do: RuntimeCheckpoint.delete(data), else: :ok
  end

  defp retire_remote_spawn(reason, %State{parent: %ParentRef{spawn_ref: request}, jido: jido})
       when not is_nil(request) and not is_nil(jido) do
    if clean_shutdown?(reason), do: Jido.AgentServer.SpawnRegistry.retire(jido, self())
    :ok
  catch
    :exit, _ -> :ok
  end

  defp retire_remote_spawn(_reason, _data), do: :ok

  defp clean_shutdown?(:normal), do: true
  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(_reason), do: false

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _reason} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp reply_action(nil, _reply), do: []
  defp reply_action(from, reply), do: [{:reply, from, reply}]

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
            0 -> {:error, normalize_startup_error(reason)}
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

  defp notify_startup(%State{startup_reply: nil}, _result), do: :ok
  defp notify_startup(%State{startup_reply: reply}, result), do: send(reply, {reply, result})

  defp normalize_startup_error({:shutdown, reason}), do: reason
  defp normalize_startup_error(:noproc), do: :not_running
  defp normalize_startup_error(reason), do: reason

  defp normalize_ready_error(
         {{:shutdown, {:bootstrap_failed, reason}}, {:gen_statem, :call, _details}}
       ),
       do: {:bootstrap_failed, reason}

  defp normalize_ready_error({:timeout, {:gen_statem, :call, _details}}), do: :timeout
  defp normalize_ready_error({:noproc, {:gen_statem, :call, _details}}), do: :not_running
  defp normalize_ready_error(reason), do: reason

  defp registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}

  defp normalize_name(name) when is_atom(name), do: {:local, name}
  defp normalize_name({:global, _term} = name), do: name
  defp normalize_name({:via, _module, _term} = name), do: name

  defp normalize_name(name) do
    raise ArgumentError,
          "Agent Server name must be an atom, :global tuple, or :via tuple, got: #{inspect(name)}"
  end

  defp admission_deadline(:infinity), do: :infinity

  defp admission_deadline(timeout) when is_integer(timeout) and timeout >= 0 do
    {node(), System.monotonic_time(:millisecond) + timeout}
  end

  defp admission_expired?(:infinity), do: false

  defp admission_expired?({origin, deadline}) when origin == node() do
    System.monotonic_time(:millisecond) >= deadline
  end

  defp admission_expired?({origin, deadline}) do
    # Compare in the clock domain that created the deadline. Count the full
    # query duration to avoid granting more time because its reply was delayed.
    started = System.monotonic_time(:millisecond)
    now = :erpc.call(origin, System, :monotonic_time, [:millisecond], 1_000)
    elapsed = System.monotonic_time(:millisecond) - started
    now + elapsed >= deadline
  catch
    _kind, _reason -> true
  end
end
