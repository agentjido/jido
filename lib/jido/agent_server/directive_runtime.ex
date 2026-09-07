defmodule Jido.AgentServer.DirectiveRuntime do
  @moduledoc false

  alias Jido.Agent.Directive.{
    AdoptChild,
    Emit,
    EmitToChild,
    EmitToParent,
    Error,
    Spawn,
    SpawnAgent,
    Stop,
    StopChild
  }

  alias Jido.AgentServer, as: Server

  alias Jido.AgentServer.{
    ChildInfo,
    ChildPlacement,
    CreationCause,
    DirectiveContext,
    ParentRef,
    State
  }

  alias Jido.AgentServer.Signal.ChildStarted
  alias Jido.RuntimeStore
  alias Jido.Signal
  alias Jido.Tracing.Context, as: TraceContext

  @relationship_hive :agent_relationships
  @reserved_child_opts [:agent, :id, :jido, :parent, :partition, :name, :register]
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
    Server.cast(parent.pid, propagate(signal, context.signal))
    {:ok, state}
  end

  def handle(%EmitToParent{}, _context, state), do: {:error, :no_parent, state}

  def handle(%EmitToChild{tag: tag, signal: signal}, context, state) do
    case State.child(state, tag) do
      %ChildInfo{kind: :agent, pid: pid} ->
        Server.cast(pid, propagate(signal, context.signal))
        {:ok, state}

      nil ->
        {:error, {:child_not_found, tag}, state}

      _child ->
        {:error, {:not_an_agent_child, tag}, state}
    end
  end

  def handle(%Error{error: error, context: error_context}, _context, state) do
    {:error, {:reported_error, error_context, error}, state}
  end

  def handle(%Spawn{} = directive, _context, state), do: spawn_generic(directive, state)

  def handle(%SpawnAgent{} = directive, context, state),
    do: spawn_agent(directive, context, state)

  def handle(%AdoptChild{} = directive, _context, state), do: adopt_child(directive, state)
  def handle(%StopChild{} = directive, _context, state), do: stop_child(directive, state)

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
    {:ok, %{directive | signal: propagate(signal, context.signal)}, target}
  end

  def prepare_signal(
        %EmitToParent{signal: signal} = directive,
        context,
        %State{parent: %ParentRef{} = parent}
      ) do
    {:ok, %{directive | signal: propagate(signal, context.signal)}, {:agent, parent.id}}
  end

  def prepare_signal(%EmitToParent{}, _context, %State{}), do: {:error, :no_parent}

  def prepare_signal(%EmitToChild{tag: tag, signal: signal} = directive, context, state) do
    case State.child(state, tag) do
      %ChildInfo{kind: :agent, id: id} ->
        {:ok, %{directive | signal: propagate(signal, context.signal)}, {:agent, id}}

      nil ->
        {:error, {:child_not_found, tag}}

      _child ->
        {:error, {:not_an_agent_child, tag}}
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
    case State.child(state, tag) do
      %ChildInfo{kind: :agent, pid: pid} -> Server.cast(pid, signal)
      nil -> {:error, {:child_not_found, tag}}
      _child -> {:error, {:not_an_agent_child, tag}}
    end
  end

  defp emit(%Emit{signal: signal, dispatch: dispatch}, context, state) do
    dispatch = dispatch || state.default_dispatch

    if is_nil(dispatch) do
      signal = propagate(signal, context.signal)
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
    signal = propagate(signal, context.signal)
    dispatch = dispatch || state.default_dispatch
    dispatch_signal(signal, dispatch, state.jido)
  end

  @doc false
  @spec dispatch_signal(Signal.t(), term(), atom() | nil) :: :ok | {:error, term()}
  def dispatch_signal(signal, dispatch, jido) do
    dispatch = inherit_bus_scope(dispatch, jido)

    case Jido.Signal.Dispatch.dispatch(signal, dispatch) do
      :ok -> :ok
      {:error, reason} -> {:error, {:emit_dispatch_failed, reason}}
    end
  rescue
    error -> {:error, {:emit_dispatch_failed, error}}
  catch
    kind, reason -> {:error, {:emit_dispatch_failed, {kind, reason}}}
  end

  defp spawn_generic(%Spawn{child_spec: child_spec}, state) do
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
      {:ok, _pid} -> {:ok, state}
      {:ok, _pid, _info} -> {:ok, state}
      :ignore -> {:ok, state}
      {:error, reason} -> {:error, {:spawn_failed, reason}, state}
    end
  end

  defp spawn_agent(%SpawnAgent{} = directive, context, %State{jido: jido} = state)
       when is_atom(jido) and not is_nil(jido) do
    with nil <- State.child(state, directive.tag),
         {:ok, request, cause, next_state} <-
           prepare_spawn(directive, CreationCause.capture(context, state), state) do
      do_spawn_agent(directive, request, cause, next_state, state)
    else
      %ChildInfo{} -> {:error, {:child_tag_in_use, directive.tag}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp spawn_agent(%SpawnAgent{}, _context, state),
    do: {:error, :jido_instance_required_for_child_agent, state}

  defp do_spawn_agent(directive, request, cause, %State{jido: jido} = state, previous) do
    child_id = Map.get(directive.opts, :id, "#{state.agent.id}/#{directive.tag}")
    child_partition = Map.get(directive.opts, :partition, state.partition)

    parent = %{
      pid: self(),
      id: state.agent.id,
      partition: state.partition,
      tag: directive.tag,
      spawn_ref: request,
      creation_cause: cause,
      meta: directive.meta
    }

    child_opts =
      directive.opts
      |> Map.drop(@reserved_child_opts)
      |> Map.put(:agent, directive.agent)
      |> Map.put(:id, child_id)
      |> Map.put(:jido, jido)
      |> Map.put(:partition, child_partition)
      |> Map.put(:parent, parent)
      |> Map.put(:register, true)
      |> Map.to_list()

    with {:ok, pid, info} <-
           start_verified_agent_process(
             directive,
             child_opts,
             child_id,
             child_partition,
             state
           ),
         :ok <-
           persist_started_agent(
             state,
             pid,
             child_id,
             child_partition,
             directive.tag,
             directive.meta,
             cause
           ) do
      child =
        ChildInfo.new!(
          pid: pid,
          ref: Process.monitor(pid),
          module: info.agent_module,
          id: child_id,
          activation_id: info.activation_id,
          creation_cause: cause,
          partition: child_partition,
          tag: directive.tag,
          kind: :agent,
          meta: directive.meta
        )

      next_state =
        state |> mark_spawn_active(directive.tag) |> State.add_child(directive.tag, child)

      Server.cast(self(), ChildStarted.for_child(state.agent.id, child))
      {:ok, next_state}
    else
      {:uncertain, reason} ->
        {:error, {:child_spawn_indeterminate, directive.tag, directive.node, request, reason},
         state}

      {:error, :spawn_request_closed} ->
        resolved = %{
          previous
          | child_spawn_requests: Map.delete(previous.child_spawn_requests, directive.tag)
        }

        {:error, {:spawn_agent_failed, :spawn_request_closed}, resolved}

      {:error, reason} ->
        {:error, {:spawn_agent_failed, reason}, previous}
    end
  end

  defp prepare_spawn(directive, cause, state) do
    target = directive.node || node()
    normalized = %{directive | node: target}

    case Map.get(state.child_spawn_requests, directive.tag) do
      %{directive: ^normalized, request_id: request, creation_cause: original_cause} ->
        {:ok, request, original_cause, state}

      %{request_id: request, directive: pending} ->
        {:error, {:child_spawn_pending, directive.tag, pending.node, request}}

      nil when target == node() ->
        {:ok, nil, cause, state}

      nil ->
        request = {System.unique_integer([:positive, :monotonic]), make_ref()}

        entry = %{
          directive: normalized,
          request_id: request,
          creation_cause: cause,
          status: :pending
        }

        requests = Map.put(state.child_spawn_requests, directive.tag, entry)
        {:ok, request, cause, %{state | child_spawn_requests: requests}}
    end
  end

  defp start_agent_process(%SpawnAgent{node: target} = directive, opts, state)
       when is_nil(target) or target == node() do
    ChildPlacement.start_local(state.jido, opts, directive.restart)
  end

  defp start_agent_process(directive, opts, state) do
    ChildPlacement.start(
      directive.node,
      state.jido,
      opts,
      directive.restart,
      state.directive_timeout
    )
  end

  defp start_verified_agent_process(directive, opts, child_id, child_partition, state) do
    with {:ok, pid, info} <- start_agent_process(directive, opts, state) do
      case verify_started_agent(info, directive, child_id, child_partition, state) do
        :ok ->
          {:ok, pid, info}

        {:error, reason} ->
          _ = ChildPlacement.stop(state.jido, pid, :identity_mismatch, state.directive_timeout)
          {:error, reason}
      end
    end
  end

  defp verify_started_agent(info, directive, child_id, child_partition, state)
       when is_map(info) do
    expected_module = expected_agent_module(directive.agent)
    parent = Map.get(info, :parent)

    mismatches =
      %{}
      |> mismatch(:id, child_id, Map.get(info, :agent_id))
      |> mismatch(:partition, child_partition, Map.get(info, :partition))
      |> mismatch(:module, expected_module, Map.get(info, :agent_module))
      |> mismatch(:parent_pid, self(), parent_value(parent, :pid))
      |> mismatch(:parent_id, state.agent.id, parent_value(parent, :id))
      |> mismatch(:parent_tag, directive.tag, parent_value(parent, :tag))

    if map_size(mismatches) == 0 do
      :ok
    else
      {:error,
       Jido.Error.validation_error("Spawned Agent identity did not match its request",
         kind: :config,
         details: %{tag: directive.tag, mismatches: mismatches}
       )}
    end
  end

  defp verify_started_agent(info, directive, _child_id, _child_partition, _state) do
    {:error,
     Jido.Error.validation_error("Spawned Agent returned invalid creation information",
       kind: :config,
       details: %{tag: directive.tag, creation_info: info}
     )}
  end

  defp expected_agent_module(%Jido.Agent{module: module}), do: module

  defp expected_agent_module(module) when is_atom(module) do
    if function_exported?(module, :__agent_config__, 0), do: module, else: :factory
  end

  defp mismatch(acc, :module, :factory, _actual), do: acc
  defp mismatch(acc, _field, expected, expected), do: acc

  defp mismatch(acc, field, expected, actual),
    do: Map.put(acc, field, %{expected: expected, actual: actual})

  defp parent_value(parent, field) when is_map(parent), do: Map.get(parent, field)
  defp parent_value(_parent, _field), do: nil

  defp mark_spawn_active(state, tag) do
    case Map.fetch(state.child_spawn_requests, tag) do
      {:ok, request} ->
        %{
          state
          | child_spawn_requests:
              Map.put(state.child_spawn_requests, tag, %{request | status: :active})
        }

      :error ->
        state
    end
  end

  defp adopt_child(%AdoptChild{} = directive, state) do
    with nil <- State.child(state, directive.tag),
         {:ok, child_pid} <- resolve_child(directive.child, state),
         false <- child_pid == self(),
         parent_ref =
           ParentRef.new!(
             pid: self(),
             id: state.agent.id,
             partition: state.partition,
             tag: directive.tag,
             meta: directive.meta
           ),
         {:ok, child_runtime} <- Server.adopt_parent(child_pid, parent_ref),
         true <- child_runtime.parent.pid == self() do
      child =
        ChildInfo.new!(
          pid: child_pid,
          ref: Process.monitor(child_pid),
          module: child_runtime.agent_module,
          id: child_runtime.agent_id,
          partition: child_runtime.partition,
          tag: directive.tag,
          kind: :agent,
          meta: directive.meta
        )

      {:ok, State.add_child(state, directive.tag, child)}
    else
      %ChildInfo{} -> {:error, {:child_tag_in_use, directive.tag}, state}
      true -> {:error, :cannot_adopt_self, state}
      false -> {:error, {:adopt_child_failed, :parent_not_attached}, state}
      {:error, reason} -> {:error, {:adopt_child_failed, reason}, state}
    end
  end

  defp stop_child(%StopChild{tag: tag, reason: reason}, state) do
    case State.child(state, tag) do
      nil ->
        case Map.get(state.child_spawn_requests, tag) do
          nil ->
            {:ok, state}

          request ->
            {:error, {:child_spawn_pending, tag, request.directive.node, request.request_id},
             state}
        end

      %ChildInfo{kind: :agent} = child ->
        case stop_agent_process(child.pid, reason, state) do
          :ok ->
            Process.demonitor(child.ref, [:flush])
            _ = delete_relationship(state, child)
            next = State.remove_child(state, tag)
            {:ok, %{next | child_spawn_requests: Map.delete(next.child_spawn_requests, tag)}}

          error ->
            {:error, {:stop_child_failed, tag, error}, state}
        end

      _child ->
        {:error, {:not_an_agent_child, tag}, state}
    end
  end

  defp stop_agent_process(pid, reason, %State{jido: jido} = state)
       when is_atom(jido) and not is_nil(jido) do
    ChildPlacement.stop(jido, pid, reason, state.directive_timeout)
  end

  defp stop_agent_process(pid, reason, _state) do
    Process.exit(pid, normalize_stop_reason(reason))
    :ok
  end

  defp resolve_child(pid, _state) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, :child_not_alive}
  end

  defp resolve_child(id, %State{jido: jido, partition: partition})
       when is_binary(id) and is_atom(jido) and not is_nil(jido) do
    case Server.whereis(Jido.registry_name(jido), id, partition: partition) do
      nil -> {:error, :child_not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_child(value, _state), do: {:error, {:invalid_child, value}}

  defp persist_relationship(
         %State{jido: jido} = state,
         child_id,
         child_partition,
         tag,
         meta,
         cause
       )
       when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.put(jido, @relationship_hive, Jido.partition_key(child_id, child_partition), %{
      parent_id: state.agent.id,
      parent_partition: state.partition,
      tag: tag,
      creation_cause: cause,
      meta: meta
    })
  end

  defp persist_relationship(_state, _child_id, _partition, _tag, _meta, _cause), do: :ok

  defp persist_started_agent(state, pid, child_id, child_partition, tag, meta, cause) do
    case persist_relationship(state, child_id, child_partition, tag, meta, cause) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = stop_agent_process(pid, {:relationship_persist_failed, reason}, state)
        {:error, {:relationship_persist_failed, reason}}
    end
  end

  defp delete_relationship(%State{jido: jido}, child)
       when is_atom(jido) and not is_nil(jido) do
    RuntimeStore.delete(
      jido,
      @relationship_hive,
      Jido.partition_key(child.id, child.partition)
    )
  end

  defp delete_relationship(_state, _child), do: :ok

  defp propagate(%Signal{} = signal, %Signal{} = source) do
    case TraceContext.propagate_to(signal, source.id) do
      {:ok, traced} -> traced
      {:error, _reason} -> signal
    end
  end

  defp inherit_bus_scope({:bus, opts}, jido) when is_atom(jido) and not is_nil(jido) do
    if Keyword.has_key?(opts, :jido),
      do: {:bus, opts},
      else: {:bus, Keyword.put(opts, :jido, jido)}
  end

  defp inherit_bus_scope(targets, jido) when is_list(targets) do
    Enum.map(targets, &inherit_bus_scope(&1, jido))
  end

  defp inherit_bus_scope(target, _jido), do: target

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

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _reason} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}
end
