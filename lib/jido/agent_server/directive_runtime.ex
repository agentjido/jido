defmodule Jido.AgentServer.DirectiveRuntime do
  @moduledoc false

  alias Jido.Agent.Directive

  alias Jido.Agent.Directive.{
    AdoptChild,
    Emit,
    EmitToChild,
    EmitToParent,
    Error,
    SpawnChild,
    SpawnProcess,
    Stop,
    StopChild
  }

  alias Jido.AgentServer, as: Server

  alias Jido.AgentServer.{
    ChildInfo,
    ChildOperations,
    DirectiveContext,
    ParentRef,
    State
  }

  alias Jido.Signal
  alias Jido.Dispatch.Preparation, as: DispatchPreparation

  @signal_directives [Emit, EmitToParent, EmitToChild]

  @type result :: {:ok, State.t()} | {:error, term(), State.t()} | {:stop, term(), State.t()}

  @doc false
  @spec handle(term(), DirectiveContext.t(), State.t()) :: result()
  def handle(%Emit{} = directive, context, state), do: emit(directive, context, state)

  def handle(
        %EmitToParent{signal: signal},
        context,
        %State{parent: %ParentRef{} = parent} = state
      ) do
    Server.cast(parent.pid, DispatchPreparation.propagate(signal, context.signal))
    {:ok, state}
  end

  def handle(%EmitToParent{}, _context, state), do: {:error, :no_parent, state}

  def handle(%EmitToChild{tag: tag, signal: signal}, context, state) do
    case agent_child(state, tag) do
      {:ok, child} ->
        Server.cast(child.pid, DispatchPreparation.propagate(signal, context.signal))
        {:ok, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  def handle(%Error{error: error, context: error_context}, _context, state) do
    {:error, {:reported_error, error_context, error}, state}
  end

  def handle(%SpawnProcess{} = directive, _context, state), do: spawn_process(directive, state)

  def handle(%SpawnChild{} = directive, context, state),
    do: ChildOperations.spawn_child(directive, context, state)

  def handle(%AdoptChild{} = directive, _context, state),
    do: ChildOperations.adopt_child(directive, state)

  def handle(%StopChild{} = directive, _context, state),
    do: ChildOperations.stop_child(directive, state)

  def handle(%Stop{reason: reason}, _context, state), do: {:stop, reason, state}

  def handle(directive, _context, state) do
    {:error, {:unsupported_agent_directive, directive}, state}
  end

  @doc false
  @spec signal_directive?(term()) :: boolean()
  def signal_directive?(%{__struct__: module}), do: module in @signal_directives
  def signal_directive?(_directive), do: false

  @doc false
  @spec validate_signal_dispatches([term()]) :: {:ok, [term()]} | {:error, term()}
  def validate_signal_dispatches(directives) do
    Enum.reduce_while(directives, :ok, fn
      %Emit{dispatch: nil}, :ok ->
        {:cont, :ok}

      %Emit{dispatch: dispatch}, :ok ->
        case validate_dispatch(dispatch) do
          {:ok, _normalized} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      _directive, :ok ->
        {:cont, :ok}
    end)
    |> then(fn
      :ok -> {:ok, directives}
      {:error, _reason} = error -> error
    end)
  end

  @doc false
  @spec prepare_signal(term(), DirectiveContext.t(), State.t()) ::
          {:ok, struct(), term()} | {:error, term()}
  def prepare_signal(%Emit{signal: signal, dispatch: dispatch} = directive, context, state) do
    target = dispatch || state.default_dispatch || {:agent, state.agent.id}
    {:ok, %{directive | signal: DispatchPreparation.propagate(signal, context.signal)}, target}
  end

  def prepare_signal(
        %EmitToParent{signal: signal} = directive,
        context,
        %State{parent: %ParentRef{} = parent}
      ) do
    {:ok, %{directive | signal: DispatchPreparation.propagate(signal, context.signal)},
     {:agent, parent.id}}
  end

  def prepare_signal(%EmitToParent{}, _context, %State{}), do: {:error, :no_parent}

  def prepare_signal(%EmitToChild{tag: tag, signal: signal} = directive, context, state) do
    case agent_child(state, tag) do
      {:ok, child} ->
        {:ok, %{directive | signal: DispatchPreparation.propagate(signal, context.signal)},
         {:agent, child.id}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec dispatch_prepared(struct(), State.t(), pid()) :: :ok | {:error, term()}
  def dispatch_prepared(%Emit{signal: signal, dispatch: dispatch}, state, agent_server) do
    case dispatch || state.default_dispatch do
      nil ->
        Server.cast(agent_server, signal)

      target ->
        dispatch_signal(signal, target, state.jido)
    end
  end

  def dispatch_prepared(%EmitToParent{signal: signal}, %State{parent: parent}, _agent_server) do
    case parent do
      %ParentRef{} -> Server.cast(parent.pid, signal)
      nil -> {:error, :no_parent}
    end
  end

  def dispatch_prepared(%EmitToChild{tag: tag, signal: signal}, state, _agent_server) do
    case agent_child(state, tag) do
      {:ok, child} -> Server.cast(child.pid, signal)
      {:error, reason} -> {:error, reason}
    end
  end

  defp agent_child(state, tag) do
    case State.child(state, tag) do
      %ChildInfo{kind: :agent} = child -> {:ok, child}
      nil -> {:error, {:child_not_found, tag}}
      _child -> {:error, {:not_an_agent_child, tag}}
    end
  end

  defp emit(%Emit{signal: signal, dispatch: dispatch}, context, state) do
    dispatch = dispatch || state.default_dispatch

    if is_nil(dispatch) do
      signal = DispatchPreparation.propagate(signal, context.signal)
      Server.cast(self(), signal)
      {:ok, state}
    else
      case dispatch_emit(%Emit{signal: signal, dispatch: dispatch}, context, state) do
        :ok -> {:ok, state}
        {:error, reason} -> {:error, reason, state}
      end
    end
  end

  @doc false
  @spec dispatch_emit(Emit.t(), DirectiveContext.t(), State.t()) :: :ok | {:error, term()}
  def dispatch_emit(%Emit{signal: signal, dispatch: dispatch}, context, state) do
    signal = DispatchPreparation.propagate(signal, context.signal)
    dispatch = dispatch || state.default_dispatch
    dispatch_signal(signal, dispatch, state.jido)
  end

  @doc false
  @spec dispatch_signal(Signal.t(), term(), atom() | nil) :: :ok | {:error, term()}
  def dispatch_signal(signal, dispatch, jido) do
    dispatch = DispatchPreparation.inherit_bus_scope(dispatch, jido)

    case Jido.Signal.Dispatch.dispatch(signal, dispatch) do
      :ok -> :ok
      {:error, reason} -> {:error, {:emit_dispatch_failed, reason}}
    end
  rescue
    error -> {:error, {:emit_dispatch_failed, error}}
  catch
    kind, reason -> {:error, {:emit_dispatch_failed, {kind, reason}}}
  end

  defp spawn_process(%SpawnProcess{child_spec: child_spec}, state) do
    try do
      result =
        cond do
          is_function(state.spawn_fun, 1) ->
            state.spawn_fun.(child_spec)

          is_atom(state.jido) ->
            DynamicSupervisor.start_child(Jido.agent_supervisor_name(state.jido), child_spec)

          true ->
            {:error, :jido_instance_required}
        end

      case result do
        {:ok, pid} when is_pid(pid) -> {:ok, state}
        {:ok, pid, _info} when is_pid(pid) -> {:ok, state}
        :ignore -> {:ok, state}
        {:error, reason} -> {:error, {:spawn_process_failed, reason}, state}
        other -> {:error, {:spawn_process_failed, {:invalid_start_result, other}}, state}
      end
    rescue
      error -> {:error, {:spawn_process_failed, error}, state}
    catch
      kind, reason -> {:error, {:spawn_process_failed, {kind, reason}}, state}
    end
  end

  defp validate_dispatch(dispatch) do
    case Jido.Signal.Dispatch.validate_opts(dispatch) do
      {:ok, normalized} ->
        {:ok, normalized}

      {:error, reason} ->
        {:error,
         Jido.Error.validation_error("Agent Emit dispatch is invalid", details: %{reason: reason})}
    end
  rescue
    error ->
      {:error,
       Jido.Error.validation_error("Agent Emit dispatch is invalid", details: %{reason: error})}
  catch
    kind, reason ->
      {:error,
       Jido.Error.validation_error("Agent Emit dispatch is invalid",
         details: %{reason: {kind, reason}}
       )}
  end

  def prepare_directives(directives, %State{} = data) do
    with :ok <- ensure_directive_limit(directives, data.max_directives_per_turn),
         :ok <- ensure_terminal_directive_last(directives),
         {:ok, directives} <- validate_signal_dispatches(directives) do
      {:ok, directives}
    end
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
end
