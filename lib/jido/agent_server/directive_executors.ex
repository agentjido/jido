defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Emit do
  @moduledoc false

  require Logger

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
      task_sup =
        if state.jido, do: Jido.task_supervisor_name(state.jido), else: Jido.TaskSupervisor

      Task.Supervisor.start_child(task_sup, fn ->
        Jido.Signal.Dispatch.dispatch(traced_signal, cfg)
      end)
    else
      Logger.warning("Jido.Signal.Dispatch not available, skipping emit")
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

  def exec(%{child_spec: child_spec, tag: tag}, _input_signal, state) do
    result =
      if is_function(state.spawn_fun, 1) do
        state.spawn_fun.(child_spec)
      else
        agent_sup =
          if state.jido, do: Jido.agent_supervisor_name(state.jido), else: Jido.AgentSupervisor

        DynamicSupervisor.start_child(agent_sup, child_spec)
      end

    case result do
      {:ok, pid} ->
        Logger.debug("Spawned child process #{inspect(pid)} with tag #{inspect(tag)}")
        {:ok, state}

      {:ok, pid, _info} ->
        Logger.debug("Spawned child process #{inspect(pid)} with tag #{inspect(tag)}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to spawn child: #{inspect(reason)}")
        {:ok, state}

      :ignored ->
        {:ok, state}
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.Schedule do
  @moduledoc false

  alias Jido.AgentServer.Signal.Scheduled
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

    Process.send_after(self(), {:scheduled_signal, traced_signal}, delay)
    {:ok, state}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.SpawnAgent do
  @moduledoc false

  require Logger

  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, State}

  def exec(%{agent: agent, tag: tag, opts: opts, meta: meta}, _input_signal, state) do
    child_id = opts[:id] || "#{state.id}/#{tag}"

    child_opts =
      [
        agent: agent,
        id: child_id,
        parent: %{
          pid: self(),
          id: state.id,
          tag: tag,
          meta: meta
        }
      ] ++ Map.to_list(Map.delete(opts, :id))

    child_opts = if state.jido, do: Keyword.put(child_opts, :jido, state.jido), else: child_opts

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
            meta: meta
          })

        new_state = State.add_child(state, tag, child_info)

        Logger.debug("AgentServer #{state.id} spawned child #{child_id} with tag #{inspect(tag)}")

        {:ok, new_state}

      {:error, reason} ->
        Logger.error("AgentServer #{state.id} failed to spawn child: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp resolve_agent_module(agent) when is_atom(agent), do: agent
  defp resolve_agent_module(%{__struct__: module}), do: module
  defp resolve_agent_module(_), do: nil
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.StopChild do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.State
  alias Jido.Tracing.Context, as: TraceContext

  def exec(%{tag: tag, reason: reason}, input_signal, state) do
    case State.get_child(state, tag) do
      nil ->
        Logger.debug("AgentServer #{state.id} cannot stop child #{inspect(tag)}: not found")
        {:ok, state}

      %{pid: pid} ->
        Logger.debug(
          "AgentServer #{state.id} stopping child #{inspect(tag)} with reason #{inspect(reason)}"
        )

        stop_signal =
          Jido.Signal.new!(
            "jido.agent.stop",
            %{reason: reason},
            source: "/agent/#{state.id}"
          )

        traced_signal =
          case TraceContext.propagate_to(stop_signal, input_signal.id) do
            {:ok, signal} -> signal
            {:error, _} -> stop_signal
          end

        _ = Jido.AgentServer.cast(pid, traced_signal)

        {:ok, state}
    end
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
