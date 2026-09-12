defmodule Jido.AgentServer.Runtime do
  @moduledoc false

  @behaviour :gen_statem

  require Logger

  @error_policy_dispatch_fallback_timeout 5_000
  @max_error_policy_tasks 32

  alias Jido.Agent
  alias Jido.Agent.Plugin, as: AgentPlugin
  alias Jido.Agent.Runner
  alias Jido.Agent.Directive
  alias Jido.Agent.Turn.Outcome
  alias Jido.Plugin
  alias Jido.AgentServer.Plugin, as: ServerPlugin
  alias Jido.Plugin.DirectiveContext, as: PluginDirectiveContext
  alias Jido.Plugin.SignalContext, as: PluginSignalContext

  alias Jido.AgentServer.{
    ActiveTurn,
    AdmissionControl,
    AdmissionDeadline,
    ChildInfo,
    ChildPlacement,
    DirectiveContext,
    DirectiveRuntime,
    ExecutionAdapter,
    Options,
    ParentRef,
    PluginLifecycle,
    RuntimeCheckpoint,
    State,
    Upgrade,
    View
  }

  alias Jido.AgentServer.Signal.{ChildExit, Orphaned}
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  @impl true
  def callback_mode, do: :handle_event_function

  @impl true
  def init(%Options{} = opts), do: init({opts, nil})

  def init({%Options{} = opts, startup_reply}) do
    Process.flag(:trap_exit, true)

    with :ok <- mark_registry_status(opts, :starting),
         {:ok, restored_agent, restored_version, initial_persistence} <-
           restore_initial_agent(opts),
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
        agent_namespace: AgentTelemetry.namespace(opts.jido),
        partition: opts.partition,
        registry: opts.registry,
        registered?: opts.register,
        exec_module: exec_module,
        exec_opts: exec_opts,
        max_postponed_signals: max_postponed_signals,
        postponed_tokens: MapSet.new(),
        turn_timeout: opts.turn_timeout,
        max_directives_per_turn: max_directives_per_turn,
        directive_timeout: opts.directive_timeout,
        readiness_timeout: opts.readiness_timeout,
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
        initial_persistence: initial_persistence,
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
        directive_task: nil,
        error_policy_tasks: %{}
      }

      span =
        AgentTelemetry.start(
          :lifecycle,
          Map.put(
            AgentTelemetry.lifecycle_metadata(data),
            :operation,
            if(initial_persistence == :restored, do: :thaw, else: :activate)
          )
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
        %State{plugin_bootstrap: %{token: token, ref: ref} = readiness} = data
      ) do
    Process.demonitor(ref, [:flush])
    cancel_task_timer(readiness.timer)
    data = %{data | plugin_bootstrap: nil}

    case persist_initial_agent(data) do
      {:ok, data} ->
        case publish_agent(data) do
          :ok ->
            AgentTelemetry.finish(data.activation_span, %{status: :ok}, %{
              state_version: data.state_version
            })

            notify_startup(data, :ok)
            data = %{data | activation_span: nil, startup_reply: nil}
            notify_parent_online(data)
            {:next_state, :idle, maybe_start_idle_timer(data, :idle)}

          {:error, reason} ->
            {:stop, {:shutdown, {:publication_failed, reason}}, data}
        end

      {:error, reason} ->
        {:stop, {:shutdown, {:persistence_failed, reason}}, data}
    end
  end

  def handle_event(
        :info,
        {:plugin_readiness, token, {:error, reason}},
        :initializing,
        %State{plugin_bootstrap: %{token: token, ref: ref} = readiness} = data
      ) do
    Process.demonitor(ref, [:flush])
    cancel_task_timer(readiness.timer)
    {:stop, {:shutdown, {:plugin_readiness_failed, reason}}, %{data | plugin_bootstrap: nil}}
  end

  def handle_event(
        :info,
        {:timeout, timer, {:plugin_readiness_timeout, token}},
        :initializing,
        %State{plugin_bootstrap: readiness} = data
      ) do
    if readiness && readiness.token == token && readiness.timer == timer do
      stop_plugin_readiness(readiness)

      error =
        Error.timeout_error("Agent Plugin readiness timed out",
          timeout: data.readiness_timeout,
          details: %{code: :plugin_callback_timeout, callback: :await_ready}
        )

      {:stop, {:shutdown, {:plugin_readiness_failed, error}}, %{data | plugin_bootstrap: nil}}
    else
      :keep_state_and_data
    end
  end

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
        spec -> {:ok, plugin_state_value(data.agent.state, spec.state_key)}
      end

    {:keep_state_and_data, [{:reply, from, reply}]}
  end

  def handle_event({:call, from}, :status, phase, %State{} = data) do
    {:keep_state_and_data, [{:reply, from, View.status(phase, data, message_queue_len())}]}
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
    {:keep_state_and_data, [{:reply, from, View.children(data)}]}
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
    {:keep_state, maybe_start_idle_timer(data, :idle), [{:reply, from, reply}]}
  end

  def handle_event(
        {:call, from},
        {:upgrade_definition, target_module, migration},
        :idle,
        %State{} = data
      ) do
    upgrade_definition(from, target_module, migration, data)
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
        reply = View.relationship_info(next_data)
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
    AdmissionControl.postpone_call(from, token, signal, deadline, data)
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :initializing, %State{} = data) do
    AdmissionControl.postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, context},
        :idle,
        %State{} = data
      ) do
    data = AdmissionControl.forget(data, token)

    if AdmissionDeadline.expired?(deadline) do
      AgentTelemetry.admission_rejected(data, signal, :deadline_expired)
      {:keep_state, data, [{:reply, from, {:error, :admission_timeout}}]}
    else
      start_turn(signal, from, context, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :idle, %State{} = data) do
    start_turn(signal, nil, %{}, AdmissionControl.forget(data, token))
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :admitting,
        %State{} = data
      ) do
    if AdmissionControl.reentrant_task_call?(from, data.admission_task) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_admission}}]}
    else
      AdmissionControl.postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :admitting, %State{} = data) do
    AdmissionControl.postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :running,
        %State{} = data
      ) do
    if AdmissionControl.reentrant_turn_call?(from, data.active) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_turn}}]}
    else
      AdmissionControl.postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :running, %State{} = data) do
    AdmissionControl.postpone_cast(token, signal, data)
  end

  def handle_event(
        {:call, from},
        {:signal, token, %Signal{} = signal, deadline, _context},
        :directing,
        %State{} = data
      ) do
    if AdmissionControl.reentrant_task_call?(from, data.directive_task) do
      {:keep_state_and_data, [{:reply, from, {:error, :reentrant_directive}}]}
    else
      AdmissionControl.postpone_call(from, token, signal, deadline, data)
    end
  end

  def handle_event(:cast, {:signal, token, %Signal{} = signal}, :directing, %State{} = data) do
    AdmissionControl.postpone_cast(token, signal, data)
  end

  def handle_event(:info, {:signal, %Signal{} = signal}, _phase, %State{}) do
    Jido.AgentServer.cast(self(), signal)
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

      {:error, {:child_tag_in_use, _tag} = reason, :stop} ->
        _ = ChildPlacement.stop(data.jido, pid, reason, data.directive_timeout)
        :keep_state_and_data

      {:error, _reason, :stop} ->
        _ = ChildPlacement.stop(data.jido, pid, :identity_mismatch, data.directive_timeout)
        :keep_state_and_data

      {:error, _reason} ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:plugin_runtime_restarting, lifecycle_pid, plugin},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    case State.child(data, key) do
      %ChildInfo{lifecycle_pid: ^lifecycle_pid} = child ->
        {:keep_state, State.add_child(data, key, %{child | pid: :restarting})}

      _child ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:plugin_runtime_bootstrap, lifecycle_pid, plugin, token},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    result =
      case State.child(data, key) do
        %ChildInfo{lifecycle_pid: ^lifecycle_pid, pid: :restarting} ->
          PluginLifecycle.replacement_child_spec(data, plugin)

        _child ->
          {:error, {:stale_plugin_runtime_bootstrap, plugin}}
      end

    send(lifecycle_pid, {:plugin_runtime_bootstrap, token, result})
    :keep_state_and_data
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
        %State{plugin_bootstrap: %{ref: ref} = readiness} = data
      ) do
    cancel_task_timer(readiness.timer)
    {:stop, {:shutdown, {:plugin_readiness_failed, reason}}, %{data | plugin_bootstrap: nil}}
  end

  def handle_event(
        :info,
        {ref, result},
        :admitting,
        %State{admission_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    release_task_result(pending)
    data = %{data | admission_task: nil}

    case result do
      {:ok, %Jido.Agent.Command{} = command} -> begin_turn_execution(command, data)
      {:error, reason} -> fail_turn(reason, :prepare, data)
      other -> fail_turn({:invalid_plugin_admission_result, other}, :prepare, data)
    end
  end

  def handle_event(
        :info,
        {:timeout, timer, {:turn_timeout, turn_id}},
        :admitting,
        %State{active: %ActiveTurn{turn_id: turn_id, timeout_timer: timer}} = data
      ) do
    timeout_admission(data)
  end

  def handle_event(
        :info,
        {:timeout, timer, {:turn_timeout, turn_id}},
        :running,
        %State{active: %ActiveTurn{turn_id: turn_id, timeout_timer: timer}} = data
      ) do
    timeout_execution(data)
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
        details: %{code: :plugin_callback_task_failed, callback: :admit, reason: reason}
      )

    fail_turn(error, :prepare, data)
  end

  def handle_event(
        :info,
        {ref, result},
        :directing,
        %State{directive_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    release_task_result(pending)
    data = %{data | directive_task: nil}

    directive_result =
      case result do
        :ok ->
          {:ok, data}

        {:dispatch_relative_signal, directive} ->
          case DirectiveRuntime.dispatch_prepared(directive, data, self()) do
            :ok -> {:ok, data}
            {:error, reason} -> {:error, reason, data}
          end

        {:error, reason} ->
          {:error, reason, data}

        other ->
          {:error, {:invalid_plugin_dispatch_result, other}, data}
      end

    complete_directive(directive_result, pending.rest, pending.context, pending.span)
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        :directing,
        %State{directive_task: %{task: %Task{ref: ref}} = pending} = data
      ) do
    cancel_task_timer(pending.timer)
    data = %{data | directive_task: nil}

    error =
      Error.execution_error("Agent Plugin Directive task exited",
        details: %{code: :plugin_callback_task_failed, callback: :dispatch, reason: reason}
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
    shutdown_task(task)
    data = %{data | directive_task: nil}

    error =
      Error.timeout_error("Agent Directive timed out",
        timeout: data.directive_timeout,
        details: %{
          code: :plugin_callback_timeout,
          callback: :dispatch,
          turn_id: data.active.turn_id
        }
      )

    complete_directive({:error, error, data}, pending.rest, pending.context, pending.span)
  end

  def handle_event(
        :info,
        {ref, result},
        _phase,
        %State{} = data
      )
      when is_map_key(data.error_policy_tasks, ref) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    release_task_result(pending)
    data = drop_error_policy_task(data, ref)

    case result do
      :ok ->
        {:keep_state, data}

      {:error, reason} ->
        {:keep_state, record_error_policy_dispatch_failure(data, reason)}

      other ->
        reason =
          Error.execution_error("Agent error Signal delivery returned an invalid result",
            details: %{result: other}
          )

        {:keep_state, record_error_policy_dispatch_failure(data, reason)}
    end
  end

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        _phase,
        %State{} = data
      )
      when is_map_key(data.error_policy_tasks, ref) do
    pending = Map.fetch!(data.error_policy_tasks, ref)
    cancel_task_timer(pending.timer)
    data = drop_error_policy_task(data, ref)

    error =
      Error.execution_error("Agent error Signal delivery task exited",
        details: %{reason: reason}
      )

    {:keep_state, record_error_policy_dispatch_failure(data, error)}
  end

  def handle_event(
        :info,
        {:timeout, timer, {:error_policy_dispatch_timeout, task_ref}},
        _phase,
        %State{} = data
      )
      when is_map_key(data.error_policy_tasks, task_ref) do
    pending = Map.fetch!(data.error_policy_tasks, task_ref)

    if pending.timer == timer do
      shutdown_task(pending.task)
      data = drop_error_policy_task(data, task_ref)

      error =
        Error.timeout_error("Agent error Signal delivery timed out",
          timeout: error_policy_dispatch_timeout(data)
        )

      {:keep_state, record_error_policy_dispatch_failure(data, error)}
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:jido_exec_adapter_started, ref, exec_pid},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter} = active} =
          data
      ) do
    adapter = ExecutionAdapter.started(adapter, exec_pid)
    {:keep_state, %{data | active: %{active | exec_handle: adapter}}}
  end

  def handle_event(
        :info,
        {:jido_exec_adapter_start_failed, ref, error},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter}} = data
      ) do
    ExecutionAdapter.cancel_timer(adapter)
    fail_turn(error, :execute, data)
  end

  def handle_event(
        :info,
        {:jido_exec_adapter_execution_failed, ref, error},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter}} = data
      ) do
    ExecutionAdapter.cancel_timer(adapter)
    fail_turn(error, :execute, data)
  end

  def handle_event(
        :info,
        {:jido_exec_adapter_callback_started, ref, token, callback},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter} = active} =
          data
      ) do
    adapter = ExecutionAdapter.callback_started(adapter, token, callback)
    {:keep_state, %{data | active: %{active | exec_handle: adapter}}}
  end

  def handle_event(
        :info,
        {:jido_exec_adapter_callback_result, ref, token, result},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter} = active} =
          data
      ) do
    adapter = ExecutionAdapter.callback_finished(adapter, token)
    data = %{data | active: %{active | exec_handle: adapter}}

    case result do
      {:done, value} ->
        ExecutionAdapter.acknowledge(adapter, token)
        finish_turn(value, data)

      :ignore ->
        {:keep_state, data}

      {:error, error} ->
        ExecutionAdapter.acknowledge(adapter, token)
        fail_turn(error, :execute, data)
    end
  end

  def handle_event(
        :info,
        {:timeout, timer, {:exec_adapter_timeout, ref, token, callback}},
        :running,
        %State{active: %ActiveTurn{exec_handle: %ExecutionAdapter{ref: ref} = adapter}} = data
      ) do
    if ExecutionAdapter.timeout?(adapter, timer, token) do
      ExecutionAdapter.stop(adapter)

      error =
        Error.timeout_error("Agent Exec callback timed out",
          timeout: adapter.timeout,
          details: %{
            code: :agent_exec_callback_timeout,
            module: adapter.module,
            callback: callback
          }
        )

      fail_turn(error, :execute, data)
    else
      :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:DOWN, monitor_ref, :process, pid, reason},
        :running,
        %State{
          active: %ActiveTurn{
            exec_handle: %ExecutionAdapter{pid: pid, monitor_ref: monitor_ref} = adapter
          }
        } = data
      ) do
    ExecutionAdapter.cancel_timer(adapter)

    error =
      Error.execution_error("Agent Exec adapter owner exited",
        details: %{
          code: :agent_exec_callback_task_failed,
          module: adapter.module,
          reason: reason
        }
      )

    fail_turn(error, :execute, data)
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

  def handle_event(:info, message, :running, %State{active: %ActiveTurn{}} = data) do
    handle_exec_message(message, data)
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
    operation = if reason == {:shutdown, :hibernate}, do: :hibernate, else: :stop
    metadata = Map.put(AgentTelemetry.lifecycle_metadata(data), :operation, operation)

    result =
      AgentTelemetry.with_span(:lifecycle, metadata, fn -> terminate_agent(reason, data) end)

    TraceContext.clear()
    notify_startup(data, {:error, normalize_startup_error(reason)})
    result
  end

  defp terminate_agent(reason, data) do
    if match?(%ActiveTurn{exec_handle: handle} when not is_nil(handle), data.active) do
      try do
        _result = cancel_exec(data.active.exec_handle, data)
        stop_exec_adapter(data.active.exec_handle)
      catch
        _kind, _reason -> :ok
      end
    end

    stop_plugin_readiness(data.plugin_bootstrap)
    stop_task(data.admission_task)
    stop_task(data.directive_task)
    Enum.each(data.error_policy_tasks, fn {_ref, pending} -> stop_task(pending) end)

    if data.directive_task do
      finish_span_error(data.directive_task.span, {:agent_stopped, reason})
    end

    AgentTelemetry.interrupted(data, reason)
    cancel_idle_timer(data)
    maybe_persist_on_stop(reason, data)
    maybe_delete_runtime_checkpoint(reason, data)
    retire_remote_spawn(reason, data)
    PluginLifecycle.stop_all(data, :shutdown)
    :ok
  end

  defp start_turn(%Signal{} = signal, from, context, %State{} = data) do
    data = cancel_idle_timer(data)
    trace = TraceContext.begin_turn(signal)
    active = ActiveTurn.new(signal, from, data.state_version, data.turn_timeout)
    data = %{data | active: active}
    metadata = data |> AgentTelemetry.turn_metadata() |> Map.merge(trace)

    semantic =
      AgentTelemetry.start(:turn, Map.merge(metadata, %{stage: :evaluate, committed?: false}), %{
        state_version_before: data.state_version
      })

    data = %{data | active: %{active | span: semantic}}
    TraceContext.put(semantic.trace)

    try do
      with {:ok, command} <- initial_command(signal, context, data) do
        data = %{data | active: %{data.active | source_signal: command.signal}}

        if AgentPlugin.prepares?(data.plugin_specs) or ServerPlugin.admits?(data.plugin_specs) do
          start_admission_task(command, data)
        else
          begin_turn_execution(command, data)
        end
      else
        {:error, reason} -> fail_turn(reason, :prepare, data)
      end
    rescue
      error ->
        AgentTelemetry.settled(data, turn_outcome(data, :failed, :prepare, error), :error)
        TraceContext.clear()
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        AgentTelemetry.settled(data, turn_outcome(data, :failed, :prepare, reason), kind)
        TraceContext.clear()
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp upgrade_definition(from, target_module, migration, %State{} = data) do
    span = AgentTelemetry.start_definition_upgrade(data, target_module)

    case Upgrade.definition(data, target_module, migration) do
      {:ok, target, plugin_specs, version} ->
        next_data = %{
          data
          | agent: target,
            plugin_specs: plugin_specs,
            state_version: version
        }

        result = {:ok, target}
        AgentTelemetry.finish_definition_upgrade(span, result, data.state_version, version)

        next_data =
          record_event(next_data, :definition_upgrade_completed, %{
            status: :ok,
            agent_module: data.agent.module,
            target_agent_module: target.module,
            state_version_before: data.state_version,
            state_version_after: version
          })

        {:keep_state, maybe_start_idle_timer(next_data, :idle), [{:reply, from, result}]}

      {:error, reason} ->
        error = {:error, reason}
        AgentTelemetry.finish_definition_upgrade(span, error, data.state_version)
        next_data = record_definition_upgrade_failure(data, target_module, reason)
        {:keep_state, maybe_start_idle_timer(next_data, :idle), [{:reply, from, error}]}

      {:stop, error} ->
        result = {:error, error}
        AgentTelemetry.finish_definition_upgrade(span, result, data.state_version)
        next_data = record_definition_upgrade_failure(data, target_module, error)

        {:stop_and_reply, {:shutdown, error}, [{:reply, from, result}], next_data}
    end
  end

  defp record_definition_upgrade_failure(data, target_module, reason) do
    record_event(data, :definition_upgrade_failed, %{
      status: :error,
      agent_module: data.agent.module,
      target_agent_module: target_module,
      state_version_before: data.state_version,
      state_version_after: nil,
      error: public_error(reason)
    })
  end

  defp start_plugin_readiness(%State{} = data) do
    owner = self()
    token = make_ref()

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          send(owner, {:plugin_readiness, token, PluginLifecycle.await_all(data)})
        end,
        [:link, :monitor]
      )

    timer = start_task_timer(data.readiness_timeout, :plugin_readiness_timeout, token)

    %{data | plugin_bootstrap: %{pid: pid, ref: ref, token: token, timer: timer}}
  end

  defp stop_plugin_readiness(%{pid: pid, ref: ref} = readiness) do
    Process.demonitor(ref, [:flush])
    if timer = Map.get(readiness, :timer), do: cancel_task_timer(timer)
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  defp stop_plugin_readiness(nil), do: :ok

  defp release_task_result(%{task: %Task{ref: ref}, timer: timer}) do
    Process.demonitor(ref, [:flush])
    cancel_task_timer(timer)
  end

  defp stop_task(%{task: %Task{} = task} = pending) do
    cancel_task_timer(Map.get(pending, :timer))
    shutdown_task(task)
  end

  defp stop_task(nil), do: :ok

  defp shutdown_task(%Task{} = task) do
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp initial_command(%Signal{} = signal, context, %State{} = data) do
    context = Map.merge(context, %{jido: data.jido, partition: data.partition})
    Jido.Agent.Command.new_trusted_agent(data.agent, signal, context)
  end

  defp start_admission_task(command, %State{} = data) do
    plugin_specs = data.plugin_specs

    with {:ok, runtime_refs} <-
           plugin_runtime_refs(data, ServerPlugin.admission_modules(plugin_specs)) do
      supervisor = Jido.task_supervisor_name(data.jido)
      trace = TraceContext.capture()

      task =
        Task.Supervisor.async(supervisor, fn ->
          TraceContext.with_context(trace, fn ->
            with {:ok, plugin_inputs} <-
                   AgentPlugin.prepare(command.agent, command.signal, plugin_specs),
                 command = %{command | plugin_inputs: plugin_inputs},
                 {:ok, command} <-
                   ServerPlugin.admit(
                     command,
                     plugin_specs,
                     runtime_refs,
                     data.state_version
                   ) do
              {:ok, command}
            end
          end)
        end)

      {:next_state, :admitting, %{data | admission_task: %{task: task, timer: nil}}}
    else
      {:error, reason} -> fail_turn(reason, :prepare, data)
    end
  rescue
    error -> fail_turn(error, :prepare, data)
  catch
    kind, reason -> fail_turn({kind, reason}, :prepare, data)
  end

  defp begin_turn_execution(%Jido.Agent.Command{} = command, %State{} = data) do
    if ActiveTurn.expired?(data.active) do
      timeout_admission(data)
    else
      do_begin_turn_execution(command, data)
    end
  end

  defp do_begin_turn_execution(%Jido.Agent.Command{} = command, %State{} = data) do
    # Admission receives the original Signal. Attach the Turn trace only at
    # the existing execution boundary, after admission has finished.
    signal =
      case Jido.Tracing.Trace.put(command.signal, data.active.span.trace) do
        {:ok, traced} -> traced
        {:error, _} -> command.signal
      end

    TraceContext.put(data.active.span.trace)
    command = %{command | signal: signal}

    case start_exec(command, data) do
      {:ok, handle, prepared} ->
        active = ActiveTurn.begin_execution(data.active, handle, prepared)
        data = %{data | active: active}

        if ActiveTurn.expired?(active) do
          timeout_execution(data)
        else
          {:next_state, :running, data}
        end

      {:error, reason} ->
        if ActiveTurn.expired?(data.active),
          do: timeout_admission(data),
          else: fail_turn(reason, :prepare, data)

      {:error, stage, reason} ->
        if ActiveTurn.expired?(data.active),
          do: timeout_admission(data),
          else: fail_turn(reason, evaluator_outcome_stage(stage), data)
    end
  end

  defp start_exec(%Jido.Agent.Command{} = command, %State{} = data) do
    exec_opts =
      Keyword.put(data.exec_opts, :task_supervisor, Jido.task_supervisor_name(data.jido))

    with {:ok, prepared} <-
           Runner.prepare_for_server(
             command,
             data.active.source_signal,
             exec_opts,
             data.plugin_specs
           ),
         {:ok, handle} <- start_async_exec(prepared, data),
         :ok <- link_exec(handle) do
      {:ok, handle, prepared}
    end
  end

  defp link_exec(%ExecutionAdapter{}), do: :ok

  defp link_exec(%{pid: pid}) when is_pid(pid) do
    Process.link(pid)
    :ok
  end

  defp start_async_exec(prepared, %State{exec_module: Jido.Exec}) do
    {:ok,
     Jido.Exec.run_async(
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

  defp start_async_exec(prepared, %State{} = data) do
    ExecutionAdapter.start(
      self(),
      Jido.task_supervisor_name(data.jido),
      data.exec_module,
      [
        prepared.turn.executable,
        prepared.turn.input,
        prepared.context,
        prepared.exec_opts
      ],
      data.directive_timeout
    )
  end

  defp finish_turn(result, %State{active: %ActiveTurn{prepared: prepared}} = data) do
    if ActiveTurn.expired?(data.active) do
      timeout_execution(data)
    else
      do_finish_turn(result, prepared, data)
    end
  end

  defp do_finish_turn(result, prepared, data) do
    case result do
      {:error, reason} ->
        fail_turn(reason, :execute, data)

      {:error, reason, _extras} ->
        fail_turn(reason, :execute, data)

      _result ->
        case Runner.finish_for_server(prepared, result) do
          {:ok, agent, directives} ->
            finish_success(agent, directives, data)

          {:error, stage, reason} ->
            if ActiveTurn.expired?(data.active),
              do: timeout_execution(data),
              else: fail_turn(reason, evaluator_outcome_stage(stage), data)
        end
    end
  end

  defp evaluator_outcome_stage(stage) when stage in [:route, :prepare, :input], do: :prepare
  defp evaluator_outcome_stage(stage) when stage in [:compose, :validate], do: :finalize

  defp finish_success(%Agent{} = agent, directives, %State{} = data) do
    result = prepare_directives(directives, data)

    if ActiveTurn.expired?(data.active) do
      timeout_execution(data)
    else
      case result do
        {:ok, directives} -> commit_turn(agent, directives, data)
        {:error, reason} -> fail_turn(reason, :finalize, data)
      end
    end
  end

  defp commit_turn(agent, directives, %State{active: %ActiveTurn{} = active} = data) do
    if ActiveTurn.expired?(active) do
      timeout_execution(data)
    else
      active = ActiveTurn.cancel_timeout(active)
      data = %{data | active: active}
      do_commit_turn(agent, directives, active, data)
    end
  end

  defp do_commit_turn(agent, directives, active, data) do
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

    if phase == :idle, do: TraceContext.clear()
    {:next_state, phase, next_data, actions}
  end

  defp fail_turn(reason, stage, %State{active: %ActiveTurn{} = active} = data) do
    signal = active.effective_signal || active.source_signal
    maybe_log_cast_failure(active.caller, signal, reason, data.agent.id)
    outcome = turn_outcome(data, outcome_status(reason), stage, reason)

    next_data =
      data
      |> Map.update!(:error_count, &(&1 + 1))
      |> complete_outcome(outcome)

    TraceContext.clear()

    decision =
      case reason do
        {:persistence_failed, failure} ->
          {:stop, {:shutdown, {:persistence_failed, failure}}, next_data}

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

  defp cancel_active(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    case cancel_exec(active.exec_handle, data) do
      :ok ->
        outcome = turn_outcome(data, :cancelled, :execute, :cancelled)
        next_data = data |> complete_outcome(outcome) |> maybe_start_idle_timer(:idle)
        TraceContext.clear()

        actions =
          reply_action(active.caller, {:error, :cancelled}) ++ [{:reply, cancel_from, :ok}]

        {:next_state, :idle, next_data, actions}

      {:error, error} ->
        outcome = turn_outcome(data, :indeterminate, :execute, error)
        next_data = complete_outcome(data, outcome)
        TraceContext.clear()

        actions =
          reply_action(active.caller, {:error, error}) ++
            [{:reply, cancel_from, {:error, error}}]

        {:stop_and_reply, {:shutdown, {:exec_cancellation_failed, error}}, actions, next_data}
    end
  end

  defp timeout_admission(%State{active: %ActiveTurn{} = active} = data) do
    stop_task(data.admission_task)
    data = %{data | admission_task: nil}
    fail_turn(turn_timeout_error(active), :prepare, data)
  end

  defp timeout_execution(%State{active: %ActiveTurn{} = active} = data) do
    case cancel_exec(active.exec_handle, data) do
      :ok ->
        stop_exec_adapter(active.exec_handle)
        fail_turn(turn_timeout_error(active), :execute, data)

      {:error, reason} ->
        error = {:turn_timeout_cancellation_failed, reason}
        outcome = turn_outcome(data, :indeterminate, :execute, error)
        next_data = complete_outcome(data, outcome)
        TraceContext.clear()
        replies = reply_action(active.caller, {:error, error})

        if replies == [] do
          {:stop, {:shutdown, error}, next_data}
        else
          {:stop_and_reply, {:shutdown, error}, replies, next_data}
        end
    end
  end

  defp turn_timeout_error(%ActiveTurn{} = active) do
    Error.timeout_error("Agent Turn timed out",
      timeout: active.timeout,
      details: %{code: :agent_turn_timeout, turn_id: active.turn_id}
    )
  end

  defp cancel_admission(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    stop_task(data.admission_task)
    outcome = turn_outcome(data, :cancelled, :prepare, :cancelled)

    next_data =
      data
      |> Map.put(:admission_task, nil)
      |> complete_outcome(outcome)
      |> maybe_start_idle_timer(:idle)

    TraceContext.clear()

    actions = reply_action(active.caller, {:error, :cancelled}) ++ [{:reply, cancel_from, :ok}]
    {:next_state, :idle, next_data, actions}
  end

  defp prepare_directives(directives, %State{} = data) do
    with :ok <- ensure_directive_limit(directives, data.max_directives_per_turn),
         :ok <- ensure_terminal_directive_last(directives),
         {:ok, directives} <- DirectiveRuntime.validate_signal_dispatches(directives) do
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
    modules = ServerPlugin.dispatch_modules(data.plugin_specs)

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
                 ServerPlugin.prepare_dispatch(
                   prepared_directive.signal,
                   data.plugin_specs,
                   runtime_refs,
                   plugin_context,
                   data.agent.state
                 ) do
            prepared_directive = Map.put(prepared_directive, :signal, signal)

            case prepared_directive do
              %Directive.Emit{} ->
                DirectiveRuntime.dispatch_prepared(prepared_directive, data, agent_server)

              _relative ->
                {:dispatch_relative_signal, prepared_directive}
            end
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
            error: public_error(reason)
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
          ServerPlugin.dispatch(plugin, runtime_ref, directive, plugin_context)
        end
      end,
      rest,
      context,
      span,
      data
    )
  end

  defp start_directive_task(fun, rest, context, span, data) do
    supervisor = Jido.task_supervisor_name(data.jido)
    trace = TraceContext.capture()
    task = Task.Supervisor.async(supervisor, fn -> TraceContext.with_context(trace, fun) end)
    timer = start_directive_timer(data.directive_timeout, task.ref)
    pending = %{task: task, timer: timer, rest: rest, context: context, span: span}
    {:keep_state, %{data | directive_task: pending}}
  rescue
    error -> complete_directive({:error, error, data}, rest, context, span)
  catch
    kind, reason -> complete_directive({:error, {kind, reason}, data}, rest, context, span)
  end

  defp start_directive_timer(:infinity, _task_ref), do: nil

  defp start_directive_timer(timeout, task_ref),
    do: :erlang.start_timer(timeout, self(), {:directive_timeout, task_ref})

  defp start_task_timer(:infinity, _tag, _task_ref), do: nil

  defp start_task_timer(timeout, tag, task_ref) do
    :erlang.start_timer(timeout, self(), {tag, task_ref})
  end

  defp cancel_task_timer(nil), do: :ok

  defp cancel_task_timer(timer) do
    _result = :erlang.cancel_timer(timer)
    :ok
  end

  defp plugin_state_value(_state, nil), do: nil
  defp plugin_state_value(state, key), do: Map.get(state, key)

  defp continue_directives([], _context, %State{active: %ActiveTurn{}} = data) do
    outcome = turn_outcome(data, :succeeded, :directive, nil)
    next_data = data |> complete_outcome(outcome) |> maybe_start_idle_timer(:idle)
    TraceContext.clear()
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

  defp message_queue_len do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, length} -> length
      nil -> 0
    end
  end

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
    handle_exec_message(active.exec_handle, message, data)
  end

  defp handle_exec_message(%ExecutionAdapter{} = adapter, message, _data) do
    ExecutionAdapter.forward(adapter, message)
    :keep_state_and_data
  end

  defp handle_exec_message(handle, message, %State{} = data) do
    case data.exec_module.handle_message(handle, message) do
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

    Jido.AgentServer.cast(self(), signal)
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
        {next_data, cancellation} = cancel_active_for_parent(next_data)

        stop_reason =
          case cancellation do
            {:indeterminate, error} -> error
            _result -> {:parent_down, reason}
          end

        {:stop, {:shutdown, stop_reason}, next_data}

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

        Jido.AgentServer.cast(self(), signal)
        {:keep_state, next_data}
    end
  end

  defp cancel_active_for_parent(%State{active: %ActiveTurn{exec_handle: handle} = active} = data)
       when not is_nil(handle) do
    {status, error} =
      case cancel_exec(handle, data) do
        :ok -> {:cancelled, {:parent_down, :cancelled}}
        {:error, reason} -> {:indeterminate, {:parent_down, {:cancellation_failed, reason}}}
      end

    outcome = turn_outcome(data, status, :execute, error)
    if active.caller, do: :gen_statem.reply(active.caller, {:error, error})
    next_data = complete_outcome(data, outcome)
    TraceContext.clear()
    {next_data, {status, error}}
  catch
    kind, reason ->
      error = {:parent_down, {:cancellation_failed, {kind, reason}}}
      outcome = turn_outcome(data, :indeterminate, :execute, error)
      if active.caller, do: :gen_statem.reply(active.caller, {:error, error})
      next_data = complete_outcome(data, outcome)
      TraceContext.clear()
      {next_data, {:indeterminate, error}}
  end

  defp cancel_active_for_parent(data), do: {data, nil}

  defp cancel_exec(%ExecutionAdapter{} = adapter, _data), do: ExecutionAdapter.cancel(adapter)
  defp cancel_exec(handle, %State{} = data), do: data.exec_module.cancel(handle)

  defp stop_exec_adapter(%ExecutionAdapter{} = adapter), do: ExecutionAdapter.stop(adapter)
  defp stop_exec_adapter(_handle), do: :ok

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
           Jido.AgentServer.whereis(Jido.registry_name(jido), binding.parent_id,
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
    case Jido.AgentServer.creation_info(pid) do
      {:ok,
       %{agent_id: ^child_id, parent: %ParentRef{pid: owner, id: parent_id, tag: ^tag} = parent} =
           info}
      when owner == self() and parent_id == data.agent.id ->
        with :ok <- verify_child_placement(pid, tag, parent, info, data), do: {:ok, info}

      _other ->
        {:error, :parent_mismatch}
    end
  end

  defp verify_child_placement(pid, tag, parent, info, data) do
    case Map.get(data.child_spawn_requests, tag) do
      %{request_id: request, directive: %{node: target} = directive} ->
        child_id = Map.get(directive.opts, :id, "#{data.agent.id}/#{tag}")
        child_partition = Map.get(directive.opts, :partition, data.partition)

        with true <- node(pid) == target and parent.spawn_ref == request,
             :ok <-
               DirectiveRuntime.verify_spawned_agent(
                 info,
                 directive,
                 child_id,
                 child_partition,
                 self(),
                 data.agent.id
               ) do
          :ok
        else
          false -> {:error, :spawn_request_mismatch, :stop}
          {:error, reason} -> {:error, reason, :stop}
        end

      nil when node(pid) == node() ->
        verify_local_child_slot(pid, tag, data)

      nil ->
        {:error, :unknown_remote_child, :stop}
    end
  end

  defp verify_local_child_slot(pid, tag, data) do
    case State.child(data, tag) do
      nil ->
        :ok

      %ChildInfo{pid: ^pid} ->
        :ok

      %ChildInfo{pid: existing_pid}
      when is_pid(existing_pid) and node(existing_pid) == node() ->
        if Process.alive?(existing_pid),
          do: {:error, {:child_tag_in_use, tag}, :stop},
          else: :ok

      %ChildInfo{} ->
        {:error, {:child_tag_in_use, tag}, :stop}
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

        Jido.AgentServer.cast(self(), signal)
        State.add_child(data, tag, child)
    end
  end

  defp directive_context(%State{} = data) do
    signal = Signal.new!(type: "jido.agent.runtime", source: "/agent/#{data.agent.id}", data: %{})

    %DirectiveContext{
      agent_id: data.agent.id,
      source_signal: signal,
      signal: signal
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

      data = start_error_policy_dispatch(signal, dispatch, data)

      {:continue, data}
    else
      {:continue, data}
    end
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
  catch
    kind, reason -> {:stop, {:error_policy_failed, {kind, reason}}, data}
  end

  defp start_error_policy_dispatch(signal, dispatch, %State{} = data) do
    if map_size(data.error_policy_tasks) >= @max_error_policy_tasks do
      error =
        Error.execution_error("Agent error Signal delivery limit was reached",
          details: %{limit: @max_error_policy_tasks}
        )

      record_error_policy_dispatch_failure(data, error)
    else
      supervisor = Jido.task_supervisor_name(data.jido)
      jido = data.jido
      trace = TraceContext.capture()

      task =
        Task.Supervisor.async(supervisor, fn ->
          TraceContext.with_context(trace, fn ->
            DirectiveRuntime.dispatch_signal(signal, dispatch, jido)
          end)
        end)

      timeout = error_policy_dispatch_timeout(data)
      timer = start_task_timer(timeout, :error_policy_dispatch_timeout, task.ref)
      pending = %{task: task, timer: timer}
      %{data | error_policy_tasks: Map.put(data.error_policy_tasks, task.ref, pending)}
    end
  rescue
    error -> record_error_policy_dispatch_failure(data, error)
  catch
    kind, reason -> record_error_policy_dispatch_failure(data, {kind, reason})
  end

  defp error_policy_dispatch_timeout(%State{directive_timeout: :infinity}),
    do: @error_policy_dispatch_fallback_timeout

  defp error_policy_dispatch_timeout(%State{directive_timeout: timeout}), do: timeout

  defp drop_error_policy_task(%State{} = data, ref) do
    %{data | error_policy_tasks: Map.delete(data.error_policy_tasks, ref)}
  end

  defp record_error_policy_dispatch_failure(%State{} = data, reason) do
    error = public_error(reason)

    Logger.error(
      "Agent error Signal delivery failed " <>
        "agent_id=#{data.agent.id} error_type=#{error.type} error_code=#{Error.code(reason)}"
    )

    record_event(data, :error_signal_delivery_failed, %{error: error})
  end

  defp turn_outcome(%State{active: active, agent: agent}, status, stage, error),
    do: ActiveTurn.outcome(active, agent.id, status, stage, error)

  defp complete_outcome(%State{} = data, %Outcome{} = outcome) do
    if data.active, do: ActiveTurn.cancel_timeout(data.active)
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
      error: if(outcome.error, do: public_error(outcome.error)),
      outcome: View.outcome_summary(outcome)
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

  defp public_error(reason), do: Error.to_map(reason)

  defp start_directive_span(directive, _context, data) do
    metadata =
      Map.merge(AgentTelemetry.turn_metadata(data), %{
        directive_module: Map.get(directive, :__struct__),
        stage: :directive,
        committed?: true
      })

    AgentTelemetry.start(
      :directive,
      metadata,
      %{directive_index: data.active.directive_completed_count},
      parent_span: data.active.span
    )
  end

  defp finish_span(nil, _measurements), do: :ok

  defp finish_span(span, measurements) do
    AgentTelemetry.finish(span, %{status: :ok}, measurements)
  end

  defp finish_span_error(nil, _reason), do: :ok

  defp finish_span_error(span, reason) do
    AgentTelemetry.finish(span, AgentTelemetry.result_metadata({:error, reason}))
  end

  defp finish_span_fault(nil, _kind, _reason, _stacktrace), do: :ok

  defp finish_span_fault(span, kind, reason, _stacktrace) do
    metadata = AgentTelemetry.result_metadata({:error, reason}) |> Map.put(:kind, kind)
    AgentTelemetry.finish(span, metadata, %{}, :exception)
  end

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

  defp restore_initial_agent(%Options{restore: false, persistence: nil} = opts) do
    {:ok, opts.agent, opts.state_version, :none}
  end

  defp restore_initial_agent(%Options{restore: false} = opts) do
    {:ok, opts.agent, opts.state_version, :create}
  end

  defp restore_initial_agent(%Options{persistence: nil, restore: :required}) do
    {:error, :persistence_not_configured}
  end

  defp restore_initial_agent(%Options{persistence: nil} = opts) do
    {agent, version} = RuntimeCheckpoint.restore(opts)
    {:ok, agent, version, :none}
  end

  defp restore_initial_agent(%Options{} = opts) do
    load_opts = [
      instance: opts.jido,
      namespace: Jido.namespace(opts.jido),
      partition: opts.partition
    ]

    case Jido.Persistence.load_agent_with_revision(
           opts.persistence,
           opts.agent.module,
           opts.agent.id,
           load_opts
         ) do
      {:ok, agent, version} ->
        {:ok, agent, version, :restored}

      {:error, :not_found} when opts.restore == :if_found ->
        {:ok, opts.agent, opts.state_version, :create}

      {:error, _reason} = error ->
        error
    end
  end

  defp persist_initial_agent(%State{initial_persistence: :create, state_version: 0} = data) do
    opts = [
      instance: data.jido,
      namespace: data.agent_namespace,
      partition: data.partition,
      revision: 0,
      reason: :activate
    ]

    case Jido.Persistence.create_agent(data.persistence, data.agent, opts) do
      :ok -> {:ok, %{data | initial_persistence: :ready}}
      {:error, _reason} = error -> error
    end
  end

  defp persist_initial_agent(%State{initial_persistence: :create, state_version: version}),
    do: {:error, {:invalid_initial_revision, version}}

  defp persist_initial_agent(%State{} = data),
    do: {:ok, %{data | initial_persistence: :ready}}

  defp publish_agent(%State{registered?: false}), do: :ok

  defp publish_agent(%State{registry: registry, agent: agent, partition: partition}) do
    key = registry_key(agent.id, partition)

    case Registry.update_value(registry, key, fn _status -> :ready end) do
      {:ready, _previous} -> :ok
      :error -> {:error, :registry_entry_not_found}
    end
  end

  defp mark_registry_status(%Options{register: false}, _status), do: :ok

  defp mark_registry_status(
         %Options{registry: registry, agent: agent, partition: partition},
         status
       ) do
    key = registry_key(agent.id, partition)

    case Registry.update_value(registry, key, fn _previous -> status end) do
      {^status, _previous} -> :ok
      :error -> {:error, :registry_entry_not_found}
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
      |> Keyword.put(:namespace, data.agent_namespace)
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

  defp notify_startup(%State{startup_reply: nil}, _result), do: :ok
  defp notify_startup(%State{startup_reply: reply}, result), do: send(reply, {reply, result})

  defp normalize_startup_error({:shutdown, reason}), do: reason
  defp normalize_startup_error(:noproc), do: :not_running
  defp normalize_startup_error(reason), do: reason

  defp registry_key(id, partition), do: {:agent, Jido.partition_key(id, partition)}
end
