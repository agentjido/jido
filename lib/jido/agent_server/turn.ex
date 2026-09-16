defmodule Jido.AgentServer.Turn do
  @moduledoc false

  alias Jido.AgentServer.Cancellation
  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.PostCommit
  alias Jido.AgentServer.TaskSupport
  alias Jido.AgentServer.TurnCompletion
  alias Jido.Agent
  alias Jido.Agent.Plugin, as: AgentPlugin
  alias Jido.Agent.Runner
  alias Jido.AgentServer.Plugin.Callbacks
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.DirectiveRuntime
  alias Jido.AgentServer.ExecutionAdapter
  alias Jido.AgentServer.Inspection
  alias Jido.AgentServer.PluginLifecycle
  alias Jido.AgentServer.State
  alias Jido.AgentServer.Storage
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  def admission_result(result, %State{admission_task: pending} = data) do
    TaskSupport.release_task_result(pending)
    data = %{data | admission_task: nil}

    case result do
      {:ok, %Jido.Agent.Command{} = command} -> begin_turn_execution(command, data)
      {:error, reason} -> TurnCompletion.fail_turn(reason, :prepare, data)
      other -> TurnCompletion.fail_turn({:invalid_plugin_admission_result, other}, :prepare, data)
    end
  end

  def admission_down(reason, %State{admission_task: pending} = data) do
    TaskSupport.cancel_task_timer(pending.timer)
    data = %{data | admission_task: nil}

    error =
      Error.execution_error("Agent Plugin admission task exited",
        details: %{code: :plugin_callback_task_failed, callback: :admit, reason: reason}
      )

    TurnCompletion.fail_turn(error, :prepare, data)
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
    TurnCompletion.fail_turn(error, :execute, data)
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
        TurnCompletion.fail_turn(error, :execute, data)
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

      TurnCompletion.fail_turn(error, :execute, data)
    else
      :keep_state_and_data
    end
  end

  def handle_event(:info, message, :running, %State{active: %ActiveTurn{}} = data),
    do: handle_exec_message(message, data)

  def adapter_down(reason, %State{active: %ActiveTurn{exec_handle: adapter}} = data) do
    ExecutionAdapter.cancel_timer(adapter)

    error =
      Error.execution_error("Agent Exec adapter owner exited",
        details: %{
          code: :agent_exec_callback_task_failed,
          module: adapter.module,
          reason: reason
        }
      )

    TurnCompletion.fail_turn(error, :execute, data)
  end

  def start_turn(%Signal{} = signal, from, context, %State{} = data) do
    data = Idle.cancel_idle_timer(data)
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

        if AgentPlugin.prepares?(data.plugin_specs) or Callbacks.admits?(data.plugin_specs) do
          start_admission_task(command, data)
        else
          begin_turn_execution(command, data)
        end
      else
        {:error, reason} -> TurnCompletion.fail_turn(reason, :prepare, data)
      end
    rescue
      error ->
        AgentTelemetry.settled(
          data,
          TurnCompletion.turn_outcome(data, :failed, :prepare, error),
          :error
        )

        TraceContext.clear()
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        AgentTelemetry.settled(
          data,
          TurnCompletion.turn_outcome(data, :failed, :prepare, reason),
          kind
        )

        TraceContext.clear()
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp initial_command(%Signal{} = signal, context, %State{} = data) do
    context = Map.merge(context, %{jido: data.jido, partition: data.partition})
    Jido.Agent.Command.new_trusted_agent(data.agent, signal, context)
  end

  defp start_admission_task(command, %State{} = data) do
    plugin_specs = data.plugin_specs

    with {:ok, runtime_refs} <-
           PluginLifecycle.plugin_runtime_refs(data, Callbacks.admission_modules(plugin_specs)) do
      pending =
        TaskSupport.start_traced(
          data.jido,
          fn ->
            with {:ok, plugin_inputs} <-
                   AgentPlugin.prepare(command.agent, command.signal, plugin_specs),
                 command = %{command | plugin_inputs: plugin_inputs},
                 {:ok, command} <-
                   Callbacks.admit(
                     command,
                     plugin_specs,
                     runtime_refs,
                     data.state_version
                   ) do
              {:ok, command}
            end
          end,
          :infinity,
          :admission_timeout
        )

      {:next_state, :admitting, %{data | admission_task: pending}}
    else
      {:error, reason} -> TurnCompletion.fail_turn(reason, :prepare, data)
    end
  rescue
    error -> TurnCompletion.fail_turn(error, :prepare, data)
  catch
    kind, reason -> TurnCompletion.fail_turn({kind, reason}, :prepare, data)
  end

  defp begin_turn_execution(%Jido.Agent.Command{} = command, %State{} = data) do
    if ActiveTurn.expired?(data.active) do
      Cancellation.timeout_admission(data)
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
          Cancellation.timeout_execution(data)
        else
          {:next_state, :running, data}
        end

      {:error, reason} ->
        if ActiveTurn.expired?(data.active),
          do: Cancellation.timeout_admission(data),
          else: TurnCompletion.fail_turn(reason, :prepare, data)

      {:error, stage, reason} ->
        if ActiveTurn.expired?(data.active),
          do: Cancellation.timeout_admission(data),
          else: TurnCompletion.fail_turn(reason, evaluator_outcome_stage(stage), data)
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
      Cancellation.timeout_execution(data)
    else
      do_finish_turn(result, prepared, data)
    end
  end

  defp do_finish_turn(result, prepared, data) do
    case result do
      {:error, reason} ->
        TurnCompletion.fail_turn(reason, :execute, data)

      {:error, reason, _extras} ->
        TurnCompletion.fail_turn(reason, :execute, data)

      _result ->
        case Runner.finish_for_server(prepared, result) do
          {:ok, agent, directives} ->
            finish_success(agent, directives, data)

          {:error, stage, reason} ->
            if ActiveTurn.expired?(data.active),
              do: Cancellation.timeout_execution(data),
              else: TurnCompletion.fail_turn(reason, evaluator_outcome_stage(stage), data)
        end
    end
  end

  defp evaluator_outcome_stage(stage) when stage in [:route, :prepare, :input], do: :prepare
  defp evaluator_outcome_stage(stage) when stage in [:compose, :validate], do: :finalize

  defp finish_success(%Agent{} = agent, directives, %State{} = data) do
    result = DirectiveRuntime.prepare_directives(directives, data)

    if ActiveTurn.expired?(data.active) do
      Cancellation.timeout_execution(data)
    else
      case result do
        {:ok, directives} -> commit_turn(agent, directives, data)
        {:error, reason} -> TurnCompletion.fail_turn(reason, :finalize, data)
      end
    end
  end

  defp commit_turn(agent, directives, %State{active: %ActiveTurn{} = active} = data) do
    if ActiveTurn.expired?(active) do
      Cancellation.timeout_execution(data)
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
        fn -> Storage.persist_commit(data, agent, version) end
      )

    case result do
      :ok -> commit_checkpointed_turn(agent, directives, version, active, data)
      {:error, reason} -> TurnCompletion.fail_turn({:persistence_failed, reason}, :commit, data)
    end
  end

  defp commit_checkpointed_turn(agent, directives, version, active, data) do
    directive_count = length(directives)
    committed_active = ActiveTurn.mark_committed(active, version, directive_count)

    next_data =
      data
      |> Map.merge(%{
        agent: agent,
        state_version: version,
        active: committed_active
      })
      |> Inspection.record_event(:turn_committed, %{
        turn_id: active.turn_id,
        signal_id: active.effective_signal.id,
        signal_type: active.effective_signal.type,
        state_version: version,
        directive_count: directive_count
      })

    AgentTelemetry.committed(next_data, version, directive_count)

    notifications = Callbacks.commit_modules(data.plugin_specs)

    post_commit_actions =
      case notifications do
        [] -> PostCommit.directive_actions(directives, agent.id, active)
        modules -> [{:next_event, :internal, {:after_commit, modules, directives}}]
      end

    actions = TurnCompletion.reply_action(active.caller, {:ok, agent}) ++ post_commit_actions
    phase = if post_commit_actions == [], do: :idle, else: :directing

    next_data =
      if phase == :idle do
        outcome = TurnCompletion.turn_outcome(next_data, :succeeded, :commit, nil)

        next_data
        |> TurnCompletion.complete_outcome(outcome)
        |> Idle.maybe_start_idle_timer(phase)
      else
        Idle.maybe_start_idle_timer(next_data, phase)
      end

    if phase == :idle, do: TraceContext.clear()
    {:next_state, phase, next_data, actions}
  end

  def handle_exec_message(message, %State{active: %ActiveTurn{} = active} = data) do
    handle_exec_message(active.exec_handle, message, data)
  end

  def handle_exec_message(%ExecutionAdapter{} = adapter, message, _data) do
    ExecutionAdapter.forward(adapter, message)
    :keep_state_and_data
  end

  def handle_exec_message(handle, message, %State{} = data) do
    case data.exec_module.handle_message(handle, message) do
      {:done, result} -> finish_turn(result, data)
      :ignore -> :keep_state_and_data
      {:error, error} -> TurnCompletion.fail_turn(error, :execute, data)
    end
  end
end
