defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Emit do
  @moduledoc false

  require Logger

  alias Jido.Runtime.Tasking
  alias Jido.Tracing.Context, as: TraceContext

  def exec(%{signal: signal, dispatch: dispatch}, input_signal, state) do
    cfg = dispatch || state.default_dispatch

    traced_signal =
      case TraceContext.propagate_to(signal, input_signal.id) do
        {:ok, s} -> s
        {:error, _} -> signal
      end

    dispatch_signal(traced_signal, cfg, state)

    {:async, nil, state}
  end

  defp dispatch_signal(traced_signal, nil, _state) do
    Logger.debug("Emit directive with no dispatch config, signal: #{traced_signal.type}")
  end

  defp dispatch_signal(traced_signal, cfg, state) do
    if Code.ensure_loaded?(Jido.Signal.Dispatch) do
      dispatch_signal_async(traced_signal, cfg, state)
    else
      Logger.warning("Jido.Signal.Dispatch not available, skipping emit")
    end
  end

  defp dispatch_signal_async(traced_signal, cfg, state) do
    case Tasking.start_child(
           fn ->
             Jido.Signal.Dispatch.dispatch(traced_signal, cfg)
           end,
           jido: state.jido
         ) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning("Emit dispatch dropped: failed to start async task (#{inspect(reason)})")
        :ok
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Error do
  @moduledoc false

  alias Jido.AgentServer.ErrorPolicy

  def exec(error_directive, _input_signal, state) do
    ErrorPolicy.handle(error_directive, state)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Spawn do
  @moduledoc false

  require Logger

  alias Jido.Agent.Directive
  alias Jido.AgentServer.{ChildInfo, State}

  def exec(%{child_spec: child_spec, tag: tag}, input_signal, state) do
    result =
      if is_function(state.spawn_fun, 1) do
        state.spawn_fun.(child_spec)
      else
        with {:ok, agent_sup} <- resolve_agent_supervisor(state) do
          DynamicSupervisor.start_child(agent_sup, child_spec)
        end
      end

    case result do
      {:ok, pid} ->
        Logger.debug("Spawned child process #{inspect(pid)} with tag #{inspect(tag)}")
        {:ok, maybe_track_spawned_child(state, pid, tag, child_spec)}

      {:ok, pid, _info} ->
        Logger.debug("Spawned child process #{inspect(pid)} with tag #{inspect(tag)}")
        {:ok, maybe_track_spawned_child(state, pid, tag, child_spec)}

      {:error, reason} ->
        {:ok, enqueue_spawn_error(state, input_signal, child_spec, tag, reason)}

      :ignored ->
        {:ok, state}
    end
  end

  defp maybe_track_spawned_child(state, pid, nil, child_spec) when is_pid(pid) do
    maybe_track_spawned_child(state, pid, {:spawn, pid}, child_spec)
  end

  defp maybe_track_spawned_child(state, pid, tag, child_spec) when is_pid(pid) do
    ref = Process.monitor(pid)
    module = child_spec_module(child_spec)

    child_info =
      ChildInfo.new!(%{
        pid: pid,
        ref: ref,
        module: module,
        id: "#{inspect(tag)}-#{inspect(pid)}",
        tag: tag,
        meta: %{directive: :spawn}
      })

    State.add_child(state, tag, child_info)
  end

  defp child_spec_module(%{start: {module, _fun, _args}}), do: module
  defp child_spec_module({module, _args}) when is_atom(module), do: module
  defp child_spec_module(module) when is_atom(module), do: module
  defp child_spec_module(_), do: nil

  defp enqueue_spawn_error(state, input_signal, child_spec, tag, reason) do
    error =
      Jido.Error.execution_error(
        "Failed to spawn child",
        details: %{reason: inspect(reason), tag: tag, child_spec: inspect(child_spec)}
      )

    directive = %Directive.Error{error: error, context: :spawn}

    case State.enqueue(state, input_signal, directive) do
      {:ok, enqueued_state} ->
        enqueued_state

      {:error, :queue_overflow} ->
        Logger.error(
          "Failed to enqueue spawn error directive due to queue overflow: #{inspect(reason)}"
        )

        state
    end
  end

  defp resolve_agent_supervisor(state) do
    case state.jido do
      jido when is_atom(jido) ->
        maybe_resolve_named_supervisor(Jido.agent_supervisor_name(jido))

      _ ->
        maybe_resolve_named_supervisor(Jido.AgentSupervisor)
    end
  end

  defp maybe_resolve_named_supervisor(supervisor) when is_atom(supervisor) do
    case Process.whereis(supervisor) do
      pid when is_pid(pid) -> {:ok, supervisor}
      nil -> {:error, :not_found}
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Schedule do
  @moduledoc false

  alias Jido.AgentServer.Signal.Scheduled
  alias Jido.AgentServer.State
  alias Jido.Tracing.Context, as: TraceContext

  def exec(%{delay_ms: delay, message: message}, input_signal, state) do
    signal =
      case message do
        %Jido.Signal{} = s ->
          s

        other ->
          Scheduled.new!(
            %{message: other},
            source: "/agent/#{state.id}"
          )
      end

    traced_signal =
      case TraceContext.propagate_to(signal, input_signal.id) do
        {:ok, s} -> s
        {:error, _} -> signal
      end

    message_ref = make_ref()
    timer_ref = Process.send_after(self(), {:scheduled_signal, message_ref, traced_signal}, delay)
    {:ok, State.put_scheduled_timer(state, message_ref, timer_ref)}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.SpawnAgent do
  @moduledoc false

  require Logger

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, State}

  def exec(%{agent: agent, tag: tag, opts: opts, meta: meta}, input_signal, state) do
    child_id = opts[:id] || "#{state.id}/#{tag}"
    normalized_meta = normalize_spawn_agent_meta(meta)

    child_opts =
      [
        agent: agent,
        id: child_id,
        parent: %{
          pid: self(),
          id: state.id,
          tag: tag,
          meta: normalized_meta
        }
      ] ++ Map.to_list(Map.delete(opts, :id))

    child_opts = if state.jido, do: Keyword.put(child_opts, :jido, state.jido), else: child_opts
    child_opts = Keyword.put(child_opts, :restart, :temporary)

    case AgentServer.start(child_opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: resolve_agent_module(agent),
            id: child_id,
            tag: tag,
            meta: Map.put(normalized_meta, :directive, :spawn_agent)
          })

        new_state = State.add_child(state, tag, child_info)

        Logger.debug("AgentServer #{state.id} spawned child #{child_id} with tag #{inspect(tag)}")

        {:ok, new_state}

      {:error, reason} ->
        {:ok, enqueue_spawn_agent_error(state, input_signal, agent, tag, child_id, reason)}
    end
  end

  defp resolve_agent_module(agent) when is_atom(agent), do: agent
  defp resolve_agent_module(%{__struct__: module}), do: module
  defp resolve_agent_module(_), do: nil

  defp enqueue_spawn_agent_error(state, input_signal, agent, tag, child_id, reason) do
    error =
      Jido.Error.execution_error(
        "Failed to spawn child agent",
        details: %{
          reason: inspect(reason),
          tag: tag,
          child_id: child_id,
          agent: inspect(agent)
        }
      )

    directive = %Directive.Error{error: error, context: :spawn_agent}

    case State.enqueue(state, input_signal, directive) do
      {:ok, enqueued_state} ->
        enqueued_state

      {:error, :queue_overflow} ->
        Logger.error(
          "Failed to enqueue spawn_agent error directive due to queue overflow: #{inspect(reason)}"
        )

        state
    end
  end

  defp normalize_spawn_agent_meta(meta) when is_map(meta), do: meta
  defp normalize_spawn_agent_meta(_meta), do: %{}
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.StopChild do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.State
  alias Jido.Runtime.Tasking
  alias Jido.RuntimeDefaults

  def exec(%{tag: tag, reason: reason}, _input_signal, state) do
    case State.get_child(state, tag) do
      nil ->
        Logger.debug("AgentServer #{state.id} cannot stop child #{inspect(tag)}: not found")
        {:ok, state}

      %{pid: pid} ->
        Logger.debug(
          "AgentServer #{state.id} stopping child #{inspect(tag)} with reason #{inspect(reason)}"
        )

        start_async_stop_child(state, tag, pid, reason)

        {:ok, state}
    end
  end

  defp start_async_stop_child(state, tag, pid, reason) do
    case Tasking.start_child(
           fn ->
             GenServer.stop(pid, reason, RuntimeDefaults.stop_child_shutdown_timeout())
           end,
           jido: state.jido
         ) do
      {:ok, _pid} ->
        :ok

      {:error, task_reason} ->
        Logger.warning(
          "AgentServer #{state.id} failed to start async stop for child #{inspect(tag)}: #{inspect(task_reason)}"
        )

        stop_child_now(state, tag, pid, reason)
    end
  end

  defp stop_child_now(state, tag, pid, reason) when is_pid(pid) do
    GenServer.stop(pid, reason, RuntimeDefaults.stop_child_shutdown_timeout())
    :ok
  catch
    :exit, stop_reason ->
      Logger.warning(
        "AgentServer #{state.id} failed to synchronously stop child #{inspect(tag)}: #{inspect(stop_reason)}"
      )

      :ok
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Stop do
  @moduledoc false

  def exec(%{reason: reason}, _input_signal, state) do
    {:stop, reason, state}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Any do
  @moduledoc false

  require Logger

  def exec(directive, _input_signal, state) do
    Logger.debug("Ignoring unknown directive: #{inspect(directive.__struct__)}")
    {:ok, state}
  end
end
