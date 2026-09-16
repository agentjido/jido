defmodule Jido.AgentServer.ServerLifecycle do
  @moduledoc false

  alias Jido.AgentServer.Cancellation
  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.PostCommit
  alias Jido.AgentServer.TaskSupport
  alias Jido.Agent
  alias Jido.Plugin
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.ChildLifecycle
  alias Jido.AgentServer.ExecutionAdapter
  alias Jido.AgentServer.Options
  alias Jido.AgentServer.PluginLifecycle
  alias Jido.AgentServer.RegistrationGuard
  alias Jido.AgentServer.State
  alias Jido.AgentServer.Storage
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  def init(%Options{} = opts), do: init({opts, nil})

  def init({%Options{} = opts, startup_reply}) do
    Process.flag(:trap_exit, true)

    with :ok <- claim_registration(opts),
         :ok <- mark_registry_status(opts, :starting),
         {:ok, restored_agent, restored_version, initial_persistence} <-
           Storage.restore_initial_agent(opts),
         {:ok, agent} <- Agent.validate_instance(restored_agent),
         {:ok, plugin_specs} <- Plugin.normalize_all(agent.plugins),
         {:ok, exec_module} <- Options.validate_exec_module(opts.exec_module),
         {:ok, exec_opts} <- Options.validate_keyword(opts.exec_opts, :exec_opts),
         {:ok, max_postponed_signals} <-
           Options.validate_limit(opts.max_postponed_signals, :max_postponed_signals),
         {:ok, max_directives_per_turn} <-
           Options.validate_limit(opts.max_directives_per_turn, :max_directives_per_turn) do
      parent = opts |> ChildLifecycle.restore_parent(agent) |> ChildLifecycle.monitor_parent()

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
        cancel_task: nil,
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
    TaskSupport.cancel_task_timer(readiness.timer)
    data = %{data | plugin_bootstrap: nil}

    case Storage.persist_initial_agent(data) do
      {:ok, data} ->
        case publish_agent(data) do
          :ok ->
            AgentTelemetry.finish(data.activation_span, %{status: :ok}, %{
              state_version: data.state_version
            })

            notify_startup(data, :ok)
            data = %{data | activation_span: nil, startup_reply: nil}
            ChildLifecycle.notify_parent_online(data)
            {:next_state, :idle, Idle.maybe_start_idle_timer(data, :idle)}

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
    TaskSupport.cancel_task_timer(readiness.timer)
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

  def handle_event(
        :info,
        {:DOWN, ref, :process, _pid, reason},
        :initializing,
        %State{plugin_bootstrap: %{ref: ref} = readiness} = data
      ) do
    TaskSupport.cancel_task_timer(readiness.timer)
    {:stop, {:shutdown, {:plugin_readiness_failed, reason}}, %{data | plugin_bootstrap: nil}}
  end

  def handle_event(:info, {:plugin_readiness, _, _}, :initializing, %State{}),
    do: :keep_state_and_data

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
    if data.cancel_task do
      TaskSupport.stop_task(data.cancel_task)
      if data.active, do: Cancellation.stop_exec_adapter(data.active.exec_handle)
    else
      terminate_active_exec(data)
    end

    stop_plugin_readiness(data.plugin_bootstrap)
    TaskSupport.stop_task(data.admission_task)
    TaskSupport.stop_task(data.commit_task)
    TaskSupport.stop_task(data.directive_task)
    Enum.each(data.error_policy_tasks, fn {_ref, pending} -> TaskSupport.stop_task(pending) end)

    if data.commit_task do
      PostCommit.finish_span_error(data.commit_task.span, {:agent_stopped, reason})
    end

    if data.directive_task do
      PostCommit.finish_span_error(data.directive_task.span, {:agent_stopped, reason})
    end

    AgentTelemetry.interrupted(data, reason)
    Idle.cancel_idle_timer(data)
    Storage.persist_on_stop(reason, data)
    Storage.delete_runtime_checkpoint(reason, data)
    ChildLifecycle.retire_remote_spawn(reason, data)
    PluginLifecycle.stop_all(data, :shutdown)
    :ok
  end

  defp terminate_active_exec(data) do
    if match?(%ActiveTurn{exec_handle: handle} when not is_nil(handle), data.active) do
      try do
        case data.active.exec_handle do
          %ExecutionAdapter{} = adapter -> Cancellation.stop_exec_adapter(adapter)
          handle -> _result = Cancellation.cancel_exec(handle, data)
        end
      catch
        _kind, _reason -> :ok
      end
    end
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

    timer = TaskSupport.start_task_timer(data.readiness_timeout, :plugin_readiness_timeout, token)

    %{data | plugin_bootstrap: %{pid: pid, ref: ref, token: token, timer: timer}}
  end

  defp stop_plugin_readiness(%{pid: pid, ref: ref} = readiness) do
    Process.demonitor(ref, [:flush])
    if timer = Map.get(readiness, :timer), do: TaskSupport.cancel_task_timer(timer)
    if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    :ok
  end

  defp stop_plugin_readiness(nil), do: :ok
  defp publish_agent(%State{registered?: false}), do: :ok

  defp publish_agent(%State{registry: registry, agent: agent, partition: partition}) do
    key = RegistrationGuard.registry_key(agent.id, partition)

    case Registry.update_value(registry, key, fn _status -> :ready end) do
      {:ready, _previous} -> :ok
      :error -> {:error, :registry_entry_not_found}
    end
  end

  defp claim_registration(%Options{register: true, jido: jido} = opts)
       when is_atom(jido) and not is_nil(jido) do
    RegistrationGuard.claim(
      jido,
      RegistrationGuard.registry_key(opts.agent.id, opts.partition),
      self()
    )
  end

  defp claim_registration(%Options{}), do: :ok

  def recover_registry_registration(pid, phase, %State{registered?: true} = data) do
    if Process.whereis(data.registry) == pid do
      key = RegistrationGuard.registry_key(data.agent.id, data.partition)
      value = if phase == :initializing, do: :starting, else: :ready

      result =
        try do
          case Registry.register(data.registry, key, value) do
            {:ok, _owner} ->
              :ok

            {:error, {:already_registered, owner}} when owner == self() ->
              case Registry.update_value(data.registry, key, fn _previous -> value end) do
                {^value, _previous} -> :ok
                :error -> :retry
              end

            {:error, _reason} ->
              :retry
          end
        catch
          :exit, _reason -> :retry
        end

      if result == :retry,
        do: Process.send_after(self(), {:jido_registry_recover, pid}, 20)
    end

    :keep_state_and_data
  end

  def recover_registry_registration(_pid, _phase, %State{}), do: :keep_state_and_data

  defp mark_registry_status(%Options{register: false}, _status), do: :ok

  defp mark_registry_status(
         %Options{registry: registry, agent: agent, partition: partition},
         status
       ) do
    key = RegistrationGuard.registry_key(agent.id, partition)

    case Registry.update_value(registry, key, fn _previous -> status end) do
      {^status, _previous} -> :ok
      :error -> {:error, :registry_entry_not_found}
    end
  end

  defp notify_startup(%State{startup_reply: nil}, _result), do: :ok
  defp notify_startup(%State{startup_reply: reply}, result), do: send(reply, {reply, result})

  def normalize_startup_error({:shutdown, reason}), do: reason
  def normalize_startup_error(:noproc), do: :not_running
  def normalize_startup_error(reason), do: reason
end
