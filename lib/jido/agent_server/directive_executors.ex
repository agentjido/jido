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
    send(self(), {:signal, traced_signal})
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

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.RunInstruction do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.State
  alias Jido.Observe.Config, as: ObserveConfig

  def exec(
        %{instruction: instruction, result_action: result_action, meta: meta},
        input_signal,
        state
      ) do
    enriched_instruction = %{
      instruction
      | context: Map.put(instruction.context || %{}, :state, state.agent.state)
    }

    execution_payload =
      enriched_instruction
      |> then(fn instruction ->
        exec_opts = ObserveConfig.action_exec_opts(state.jido, instruction.opts)
        Jido.Exec.run(%{instruction | opts: exec_opts})
      end)
      |> normalize_result_payload()
      |> Map.put(:instruction, instruction)
      |> Map.put(:meta, meta || %{})

    {agent, directives} =
      state.agent_module.cmd(
        state.agent,
        {result_action, execution_payload},
        __jido_instance__: state.jido
      )

    state = State.update_agent(state, agent)

    case State.enqueue_all(state, input_signal, List.wrap(directives)) do
      {:ok, state} ->
        {:ok, state}

      {:error, :queue_overflow} ->
        Logger.warning("AgentServer #{state.id} queue overflow, dropping directives")
        {:ok, state}
    end
  end

  defp normalize_result_payload({:ok, result}) do
    %{
      status: :ok,
      result: result,
      effects: []
    }
  end

  defp normalize_result_payload({:ok, result, effects}) do
    %{
      status: :ok,
      result: result,
      effects: List.wrap(effects)
    }
  end

  defp normalize_result_payload({:error, reason}) do
    %{
      status: :error,
      reason: reason,
      effects: []
    }
  end

  defp normalize_result_payload({:error, reason, effects}) do
    %{
      status: :error,
      reason: reason,
      effects: List.wrap(effects)
    }
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

  alias Jido.Agent.Directive
  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, State}
  alias Jido.RuntimeStore

  @relationship_hive :relationships

  def exec(
        %{agent: agent, tag: tag, opts: opts, meta: meta, restart: restart},
        _input_signal,
        state
      ) do
    with :ok <- Directive.validate_restart_policy(restart),
         :ok <- Directive.validate_spawn_agent_opts(opts) do
      spawn_child(state, agent, tag, opts, meta, restart)
    else
      {:error, reason} ->
        Logger.error("AgentServer #{state.id} failed to spawn child: #{reason}")
        {:ok, state}
    end
  end

  defp resolve_agent_module(agent) when is_atom(agent), do: agent
  defp resolve_agent_module(%{__struct__: module}), do: module
  defp resolve_agent_module(_), do: nil

  defp spawn_child(state, agent, tag, opts, meta, restart) do
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

    child_opts =
      if state.jido, do: Keyword.put(child_opts, :jido, state.jido), else: child_opts

    child_spec = Supervisor.child_spec({AgentServer, child_opts}, restart: restart)

    supervisor =
      if state.jido, do: Jido.agent_supervisor_name(state.jido), else: Jido.AgentSupervisor

    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} ->
        case persist_relationship(state, child_id, tag, meta) do
          :ok ->
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

            Logger.debug(
              "AgentServer #{state.id} spawned child #{child_id} with tag #{inspect(tag)}"
            )

            {:ok, new_state}

          {:error, reason} ->
            _ = DynamicSupervisor.terminate_child(supervisor, pid)

            Logger.error(
              "AgentServer #{state.id} failed to persist relationship for child #{child_id}: #{inspect(reason)}"
            )

            {:ok, state}
        end

      {:error, reason} ->
        Logger.error(
          "AgentServer #{state.id} failed to spawn child with restart #{inspect(restart)}: #{inspect(reason)}"
        )

        {:ok, state}
    end
  end

  defp persist_relationship(state, child_id, tag, meta) do
    RuntimeStore.put(state.jido, @relationship_hive, child_id, %{
      parent_id: state.id,
      tag: tag,
      meta: normalize_meta(meta)
    })
  end

  defp normalize_meta(meta) when is_map(meta), do: meta
  defp normalize_meta(_meta), do: %{}
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.AdoptChild do
  @moduledoc false

  require Logger

  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, ParentRef, State}

  def exec(%{child: child, tag: tag, meta: meta}, _input_signal, state) do
    with :ok <- ensure_tag_available(state, tag),
         {:ok, child_pid} <- resolve_child(child, state),
         :ok <- ensure_not_self(child_pid),
         {:ok, child_runtime} <- adopt_child(child_pid, tag, meta, state) do
      child_info =
        ChildInfo.new!(%{
          pid: child_pid,
          ref: Process.monitor(child_pid),
          module: child_runtime.agent_module,
          id: child_runtime.id,
          tag: tag,
          meta: meta
        })

      Logger.debug(
        "AgentServer #{state.id} adopted child #{child_runtime.id} with tag #{inspect(tag)}"
      )

      {:ok, State.add_child(state, tag, child_info)}
    else
      {:error, reason} ->
        Logger.warning(
          "AgentServer #{state.id} failed to adopt child #{inspect(child)} with tag #{inspect(tag)}: #{inspect(reason)}"
        )

        {:ok, state}
    end
  end

  defp ensure_tag_available(state, tag) do
    case State.get_child(state, tag) do
      nil -> :ok
      _child -> {:error, {:tag_in_use, tag}}
    end
  end

  defp resolve_child(pid, _state) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :child_not_alive}
  end

  defp resolve_child(id, state) when is_binary(id) do
    case Jido.whereis(state.jido, id) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :child_not_found}
    end
  end

  defp resolve_child(child, _state), do: {:error, {:invalid_child, child}}

  defp ensure_not_self(pid) when pid == self(), do: {:error, :cannot_adopt_self}
  defp ensure_not_self(_pid), do: :ok

  defp adopt_child(child_pid, tag, meta, state) do
    parent_ref =
      ParentRef.new!(%{
        pid: self(),
        id: state.id,
        tag: tag,
        meta: meta
      })

    AgentServer.adopt_parent(child_pid, parent_ref)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.Agent.Directive.StopChild do
  @moduledoc false

  require Logger

  alias Jido.AgentServer.State
  alias Jido.RuntimeStore
  alias Jido.Tracing.Context, as: TraceContext

  @relationship_hive :relationships

  def exec(%{tag: tag, reason: reason}, input_signal, state) do
    case State.get_child(state, tag) do
      nil ->
        Logger.debug("AgentServer #{state.id} cannot stop child #{inspect(tag)}: not found")
        {:ok, state}

      %{pid: pid, id: child_id} ->
        Logger.debug(
          "AgentServer #{state.id} stopping child #{inspect(tag)} with reason #{inspect(reason)}"
        )

        case RuntimeStore.delete(state.jido, @relationship_hive, child_id) do
          :ok ->
            :ok

          {:error, delete_reason} ->
            Logger.warning(
              "AgentServer #{state.id} failed to clear relationship for child #{child_id}: #{inspect(delete_reason)}"
            )
        end

        stop_signal =
          Jido.Signal.new!(
            "jido.agent.stop",
            %{reason: normalize_stop_reason(reason)},
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

  # Transient children only skip restart for OTP "clean" shutdown reasons.
  # Wrap custom reasons so StopChild removes the child instead of respawning it.
  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}
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
