defmodule Jido.AgentServer.PostCommit do
  @moduledoc false

  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.TaskSupport
  alias Jido.AgentServer.TurnCompletion
  require Logger
  alias Jido.Agent.Directive
  alias Jido.Plugin
  alias Jido.AgentServer.Plugin, as: ServerPlugin
  alias Jido.AgentServer.Plugin.Commit
  alias Jido.Plugin.DirectiveContext, as: PluginDirectiveContext
  alias Jido.Plugin.SignalContext, as: PluginSignalContext
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.DirectiveContext
  alias Jido.AgentServer.DirectiveRuntime
  alias Jido.AgentServer.Inspection
  alias Jido.AgentServer.PluginLifecycle
  alias Jido.AgentServer.Shutdown
  alias Jido.AgentServer.State
  alias Jido.Error
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  def commit_result(result, %State{commit_task: pending} = data) do
    TaskSupport.release_task_result(pending)
    complete_commit_notification(result, pending, %{data | commit_task: nil})
  end

  def commit_down(reason, %State{commit_task: pending} = data) do
    TaskSupport.cancel_task_timer(pending.timer)

    error =
      Error.execution_error("Agent Plugin commit notification task exited",
        details: %{code: :plugin_callback_task_failed, callback: :after_commit, reason: reason}
      )

    complete_commit_notification({:error, error}, pending, %{data | commit_task: nil}, :exit)
  end

  def commit_timeout(%State{commit_task: pending} = data) do
    TaskSupport.shutdown_task(pending.task)

    error =
      Error.timeout_error("Agent Plugin commit notification timed out",
        timeout: commit_notification_timeout(data),
        details: %{code: :plugin_callback_timeout, callback: :after_commit}
      )

    complete_commit_notification({:error, error}, pending, %{data | commit_task: nil})
  end

  def directive_result(result, %State{directive_task: pending} = data) do
    TaskSupport.release_task_result(pending)
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

  def directive_down(reason, %State{directive_task: pending} = data) do
    TaskSupport.cancel_task_timer(pending.timer)
    data = %{data | directive_task: nil}

    error =
      Error.execution_error("Agent Plugin Directive task exited",
        details: %{code: :plugin_callback_task_failed, callback: :dispatch, reason: reason}
      )

    complete_directive({:error, error, data}, pending.rest, pending.context, pending.span, :exit)
  end

  def directive_timeout(%State{directive_task: pending} = data) do
    TaskSupport.shutdown_task(pending.task)
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
        :internal,
        {:after_commit, [plugin | rest], directives},
        :directing,
        %State{} = data
      ) do
    start_commit_notification(plugin, rest, directives, data)
  end

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

  def handle_event(:internal, _event, :directing, %State{}), do: :keep_state_and_data

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
         {:ok, runtime_refs} <- PluginLifecycle.plugin_runtime_refs(data, modules) do
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
          |> Inspection.record_event(:directive_failed, %{
            turn_id: active.turn_id,
            error: Inspection.public_error(reason)
          })

        outcome =
          TurnCompletion.turn_outcome(
            next_data,
            TurnCompletion.outcome_status(reason),
            :directive,
            reason
          )

        next_data = TurnCompletion.complete_outcome(next_data, outcome)

        TurnCompletion.apply_post_commit_error_policy(outcome, next_data)

      {:stop, reason, next_data} ->
        finish_span(span, %{result: :stop})
        active = ActiveTurn.mark_directive_completed(next_data.active)
        next_data = %{next_data | active: active}
        outcome = TurnCompletion.turn_outcome(next_data, :succeeded, :directive, nil)

        {:stop, Shutdown.normalize_reason(reason),
         TurnCompletion.complete_outcome(next_data, outcome)}
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
      plugin_state: PluginLifecycle.plugin_state_value(data.agent.state, plugin.state_key),
      turn_context: context.turn_context,
      jido: data.jido,
      partition: data.partition
    }

    # A restarting Plugin can need Agent state to become ready. Resolve its
    # reference in the bounded task so the Agent can answer that state query.
    start_directive_task(
      fn ->
        with {:ok, runtime_ref} <- PluginLifecycle.plugin_runtime_ref(data, plugin) do
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
    pending =
      TaskSupport.start_traced(data.jido, fun, data.directive_timeout, :directive_timeout)
      |> Map.merge(%{rest: rest, context: context, span: span})

    {:keep_state, %{data | directive_task: pending}}
  rescue
    error -> complete_directive({:error, error, data}, rest, context, span)
  catch
    kind, reason -> complete_directive({:error, {kind, reason}, data}, rest, context, span)
  end

  defp start_commit_notification(module, rest, directives, data) do
    plugin = Enum.find(data.plugin_specs, &(&1.module == module))

    commit = %Commit{
      plugin: module,
      turn_id: data.active.turn_id,
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      plugin_state: PluginLifecycle.plugin_state_value(data.agent.state, plugin.state_key),
      state_version: data.state_version,
      jido: data.jido,
      partition: data.partition
    }

    metadata =
      Map.merge(AgentTelemetry.turn_metadata(data), %{
        stage: :after_commit,
        committed?: true,
        plugin_module: module,
        facet_module: plugin.agent_server.module
      })

    span =
      AgentTelemetry.start(:after_commit, metadata, %{state_version: data.state_version},
        parent_span: data.active.span
      )

    pending = %{rest: rest, directives: directives, span: span}
    launch_commit_notification(plugin, commit, pending, data)
  end

  defp launch_commit_notification(plugin, commit, pending, data) do
    task =
      TaskSupport.start_traced(
        data.jido,
        fn ->
          with {:ok, runtime_ref} <- PluginLifecycle.plugin_runtime_ref(data, plugin) do
            ServerPlugin.after_commit(plugin, runtime_ref, commit)
          end
        end,
        commit_notification_timeout(data),
        :after_commit_timeout
      )

    {:keep_state, %{data | commit_task: Map.merge(pending, task)}}
  rescue
    error -> complete_commit_notification({:error, error}, pending, data)
  catch
    kind, reason -> complete_commit_notification({:error, {kind, reason}}, pending, data)
  end

  defp complete_commit_notification(result, pending, data, fault_kind \\ nil)

  defp complete_commit_notification(:ok, pending, data, _fault_kind) do
    finish_span(pending.span, %{result: :ok})

    case {pending.rest, pending.directives} do
      {[], []} ->
        outcome = TurnCompletion.turn_outcome(data, :succeeded, :after_commit, nil)

        next_data =
          data |> TurnCompletion.complete_outcome(outcome) |> Idle.maybe_start_idle_timer(:idle)

        TraceContext.clear()
        {:next_state, :idle, next_data}

      {[], directives} ->
        {:keep_state, data, directive_actions(directives, data.agent.id, data.active)}

      {rest, directives} ->
        {:keep_state, data, [{:next_event, :internal, {:after_commit, rest, directives}}]}
    end
  end

  defp complete_commit_notification({:error, reason}, pending, data, fault_kind) do
    if fault_kind,
      do: finish_span_fault(pending.span, fault_kind, reason, []),
      else: finish_span_error(pending.span, reason)

    metadata = pending.span.metadata |> Map.merge(AgentTelemetry.error_metadata(reason))
    Logger.error("Agent Plugin commit notification failed", Map.to_list(metadata))

    outcome =
      TurnCompletion.turn_outcome(
        data,
        TurnCompletion.outcome_status(reason),
        :after_commit,
        reason
      )

    TurnCompletion.apply_post_commit_error_policy(
      outcome,
      TurnCompletion.complete_outcome(data, outcome)
    )
  end

  defp commit_notification_timeout(%State{directive_timeout: :infinity}), do: 5_000
  defp commit_notification_timeout(%State{directive_timeout: timeout}), do: timeout

  defp continue_directives([], _context, %State{active: %ActiveTurn{}} = data) do
    outcome = TurnCompletion.turn_outcome(data, :succeeded, :directive, nil)

    next_data =
      data |> TurnCompletion.complete_outcome(outcome) |> Idle.maybe_start_idle_timer(:idle)

    TraceContext.clear()
    {:next_state, :idle, next_data}
  end

  defp continue_directives(rest, context, data) do
    {:keep_state, data, [{:next_event, :internal, {:handle_directives, rest, context}}]}
  end

  def directive_actions([], _agent_id, _active), do: []

  def directive_actions(directives, agent_id, %ActiveTurn{} = active) do
    context = %DirectiveContext{
      turn_id: active.turn_id,
      agent_id: agent_id,
      source_signal: active.source_signal,
      signal: active.effective_signal,
      turn_context: active.turn_context
    }

    [{:next_event, :internal, {:handle_directives, directives, context}}]
  end

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

  def finish_span_error(nil, _reason), do: :ok

  def finish_span_error(span, reason) do
    AgentTelemetry.finish(span, AgentTelemetry.result_metadata({:error, reason}))
  end

  defp finish_span_fault(nil, _kind, _reason, _stacktrace), do: :ok

  defp finish_span_fault(span, kind, reason, _stacktrace) do
    metadata = AgentTelemetry.result_metadata({:error, reason}) |> Map.put(:kind, kind)
    AgentTelemetry.finish(span, metadata, %{}, :exception)
  end
end
