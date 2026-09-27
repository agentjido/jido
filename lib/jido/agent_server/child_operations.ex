defmodule Jido.AgentServer.ChildOperations do
  @moduledoc false

  alias Jido.Agent.Directive.{AdoptChild, SpawnChild, SpawnProcess, StopChild}
  alias Jido.AgentServer, as: Server

  alias Jido.AgentServer.{
    Admission,
    ChildInfo,
    ChildPlacement,
    CreationCause,
    DirectiveRuntime,
    Idle,
    ParentRef,
    PostCommit,
    Relationship,
    Shutdown,
    State,
    TaskSupport
  }

  alias Jido.AgentServer.Signal.ChildStarted

  @reserved_child_opts [:agent, :id, :jido, :parent, :partition, :name, :register]

  def handles?(%{__struct__: module}),
    do: module in [AdoptChild, SpawnChild, SpawnProcess, StopChild]

  def handles?(_directive), do: false

  def start_directive(directive, context, pending, data) do
    start_task(directive, context, Map.put(pending, :from, nil), data)
  end

  def handle_child_directive_call(directive, from, :idle, data) do
    start_task(directive, nil, %{from: from, span: nil}, data)
  end

  def handle_child_directive_call(_directive, from, phase, data) do
    case Admission.reentrant_reason(from, phase, data) do
      nil -> {:keep_state_and_data, [:postpone]}
      reason -> {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  defp start_task(directive, context, pending, data) do
    case prepare(directive, context, data) do
      {:ok, nil, next_data} -> finish({:ok, next_data}, pending)
      {:ok, operation, next_data} -> launch(operation, pending, next_data)
      {:error, reason, next_data} -> finish({:error, reason, next_data}, pending)
    end
  end

  defp launch(operation, pending, data) do
    # A local supervisor start cannot be cancelled by killing its caller.
    # Keep ownership until it replies. Remote placement keeps its RPC deadline.
    task =
      TaskSupport.start_traced(
        data.jido,
        fn -> run(operation) end,
        :infinity,
        :child_operation_timeout
      )

    pending = pending |> Map.merge(task) |> Map.put(:operation, operation)
    {:next_state, :directing, %{Idle.cancel_idle_timer(data) | child_task: pending}}
  rescue
    error -> finish(complete(operation, {:error, error}, data), pending)
  catch
    kind, reason -> finish(complete(operation, {:error, {kind, reason}}, data), pending)
  end

  def settle(event, %State{child_task: pending} = data) do
    TaskSupport.settle(pending, event)

    result =
      case event do
        {:result, result} -> result
        {:down, reason} -> {:uncertain, {:child_operation_task_down, reason}}
      end

    finish(complete(pending.operation, result, %{data | child_task: nil}), pending)
  end

  defp finish(result, %{from: nil} = pending), do: PostCommit.complete_child(result, pending)

  defp finish({:ok, data}, %{from: from}),
    do: {:next_state, :idle, Idle.maybe_start_idle_timer(data, :idle), [{:reply, from, :ok}]}

  defp finish({:error, reason, data}, %{from: from}),
    do:
      {:next_state, :idle, Idle.maybe_start_idle_timer(data, :idle),
       [{:reply, from, {:error, reason}}]}

  # Direct internal callers use the same operation and completion rules.
  def spawn_child(directive, context, state), do: execute(directive, context, state)
  def adopt_child(directive, state), do: execute(directive, nil, state)
  def stop_child(directive, state), do: execute(directive, nil, state)

  defp execute(directive, context, state) do
    case prepare(directive, context, state) do
      {:ok, nil, state} -> {:ok, state}
      {:ok, operation, state} -> complete(operation, run(operation), state)
      error -> error
    end
  end

  defp prepare(%SpawnProcess{} = directive, _context, state) do
    {:ok,
     %{kind: :process, directive: directive, jido: state.jido, spawn_fun: state.config.spawn_fun},
     state}
  end

  defp prepare(%SpawnChild{} = directive, context, %State{jido: jido} = state)
       when is_atom(jido) and not is_nil(jido) do
    with nil <- State.child(state, directive.tag),
         {:ok, request, cause, next_state} <-
           prepare_spawn(directive, CreationCause.capture(context, state), state) do
      child_id = Map.get(directive.opts, :id, "#{state.agent.id}/#{directive.tag}")
      partition = Map.get(directive.opts, :partition, state.partition)

      parent = %{
        pid: self(),
        id: state.agent.id,
        partition: state.partition,
        tag: directive.tag,
        spawn_ref: request,
        creation_cause: cause,
        meta: directive.meta
      }

      opts =
        directive.opts
        |> Map.drop(@reserved_child_opts)
        |> Map.merge(%{
          agent: directive.agent,
          id: child_id,
          jido: jido,
          partition: partition,
          parent: parent,
          register: true
        })
        |> Map.to_list()

      operation = %{
        kind: :spawn,
        tag: directive.tag,
        directive: directive,
        parent: parent,
        opts: opts,
        jido: jido,
        timeout: state.config.directive_timeout,
        id: child_id,
        partition: partition,
        previous_request: Map.get(state.child_spawn_requests, directive.tag)
      }

      {:ok, operation, next_state}
    else
      %ChildInfo{} -> {:error, {:child_tag_in_use, directive.tag}, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp prepare(%SpawnChild{}, _context, state),
    do: {:error, :jido_instance_required_for_child_agent, state}

  defp prepare(%AdoptChild{} = directive, _context, state) do
    if State.child(state, directive.tag) do
      {:error, {:child_tag_in_use, directive.tag}, state}
    else
      parent =
        ParentRef.new!(
          pid: self(),
          id: state.agent.id,
          partition: state.partition,
          tag: directive.tag,
          meta: directive.meta
        )

      {:ok,
       %{
         kind: :adopt,
         tag: directive.tag,
         directive: directive,
         parent: parent,
         jido: state.jido,
         partition: state.partition
       }, state}
    end
  end

  defp prepare(%StopChild{tag: tag, reason: reason}, _context, state) do
    case State.child(state, tag) do
      nil ->
        case Map.get(state.child_spawn_requests, tag) do
          nil ->
            {:ok, nil, state}

          %{status: :active} = request ->
            {:ok,
             %{
               kind: :stop,
               tag: tag,
               child: nil,
               jido: state.jido,
               timeout: state.config.directive_timeout,
               reason: reason,
               node: request.directive.node,
               request: %{pid: self(), tag: tag, spawn_ref: request.request_id},
               identity: %{
                 id: Map.get(request.directive.opts, :id, "#{state.agent.id}/#{tag}"),
                 partition: Map.get(request.directive.opts, :partition, state.partition)
               }
             }, state}

          request ->
            {:error, {:child_spawn_pending, tag, request.directive.node, request.request_id},
             state}
        end

      %ChildInfo{kind: :agent} = child ->
        {:ok,
         %{
           kind: :stop,
           tag: tag,
           child: child,
           jido: state.jido,
           timeout: state.config.directive_timeout,
           reason: reason
         }, state}

      _child ->
        {:error, {:not_an_agent_child, tag}, state}
    end
  end

  defp run(%{kind: :process} = operation),
    do: DirectiveRuntime.spawn_process(operation.directive, operation.jido, operation.spawn_fun)

  defp run(%{kind: :spawn, directive: directive, parent: parent} = operation) do
    with {:ok, pid, info} <- start_verified(operation),
         :ok <- persist_started(operation, pid) do
      {:ok,
       ChildInfo.new!(
         pid: pid,
         ref: nil,
         module: info.agent_module,
         id: operation.id,
         activation_id: info.activation_id,
         creation_cause: parent.creation_cause,
         partition: operation.partition,
         tag: directive.tag,
         kind: :agent,
         meta: directive.meta
       )}
    end
  end

  defp run(%{kind: :adopt, directive: directive, parent: parent} = operation) do
    with {:ok, pid} <- resolve_child(directive.child, operation),
         false <- pid == parent.pid,
         {:ok, info} <- Server.adopt_parent(pid, parent, :infinity),
         true <- info.parent.pid == parent.pid do
      {:ok,
       ChildInfo.new!(
         pid: pid,
         ref: nil,
         module: info.agent_module,
         id: info.agent_id,
         partition: info.partition,
         tag: directive.tag,
         kind: :agent,
         meta: directive.meta
       )}
    else
      true -> {:error, :cannot_adopt_self}
      false -> {:error, {:adopt_child_failed, :parent_not_attached}}
      {:error, reason} -> {:error, {:adopt_child_failed, reason}}
    end
  end

  defp run(%{kind: :stop, child: nil} = operation) do
    result =
      ChildPlacement.stop_request(
        operation.node,
        operation.jido,
        operation.request,
        operation.reason,
        operation.timeout
      )

    finish_stop(result, operation, operation.identity)
  end

  defp run(%{kind: :stop, child: child} = operation),
    do: finish_stop(stop_process(operation, child.pid, operation.reason), operation, child)

  defp finish_stop(:ok, operation, identity) do
    _ = Relationship.delete_child(operation, identity)
    :ok
  end

  defp finish_stop(error, operation, _identity),
    do: {:error, {:stop_child_failed, operation.tag, error}}

  defp start_verified(%{directive: directive, parent: parent} = operation) do
    result =
      if is_nil(directive.node) or directive.node == node(),
        do: ChildPlacement.start_local(operation.jido, operation.opts, directive.restart),
        else:
          ChildPlacement.start(
            directive.node,
            operation.jido,
            operation.opts,
            directive.restart,
            operation.timeout
          )

    with {:ok, pid, info} <- result do
      case verify_spawned_agent(
             info,
             directive,
             operation.id,
             operation.partition,
             parent.pid,
             parent.id
           ) do
        :ok ->
          {:ok, pid, info}

        {:error, reason} ->
          _ = stop_process(operation, pid, :identity_mismatch)
          {:error, reason}
      end
    end
  end

  defp persist_started(%{parent: parent} = operation, pid) do
    binding =
      Relationship.record(
        parent.id,
        parent.partition,
        parent.tag,
        parent.creation_cause,
        parent.meta
      )

    case Relationship.put(operation.jido, operation.id, operation.partition, binding) do
      :ok ->
        :ok

      {:error, reason} ->
        _ = stop_process(operation, pid, {:relationship_persist_failed, reason})
        {:error, {:relationship_persist_failed, reason}}
    end
  end

  defp stop_process(%{jido: jido, timeout: timeout}, pid, reason) when not is_nil(jido),
    do: ChildPlacement.stop(jido, pid, reason, timeout)

  defp stop_process(_operation, pid, reason) do
    Process.exit(pid, Shutdown.normalize_reason(reason))
    :ok
  end

  defp complete(%{kind: kind} = operation, {:ok, %ChildInfo{} = child}, state)
       when kind in [:spawn, :adopt] do
    child = %{child | ref: Process.monitor(child.pid)}
    next = state |> State.mark_spawn_active(child.tag) |> State.add_child(child.tag, child)
    if kind == :spawn, do: Server.cast(self(), ChildStarted.for_child(operation.parent.id, child))
    {:ok, next}
  end

  defp complete(%{kind: :stop, tag: tag, child: child}, :ok, state) do
    if child, do: Process.demonitor(child.ref, [:flush])
    next = State.remove_child(state, tag)
    {:ok, %{next | child_spawn_requests: Map.delete(next.child_spawn_requests, tag)}}
  end

  defp complete(%{kind: :process}, :ok, state), do: {:ok, state}

  defp complete(%{kind: :spawn} = operation, {:uncertain, reason}, state) do
    {:error,
     {:child_spawn_indeterminate, operation.directive.tag, operation.directive.node || node(),
      operation.parent.spawn_ref, reason}, state}
  end

  defp complete(%{kind: :spawn} = operation, {:error, reason}, state) do
    tag = operation.directive.tag
    previous = if reason == :spawn_request_closed, do: nil, else: operation.previous_request

    requests =
      if previous,
        do: Map.put(state.child_spawn_requests, tag, previous),
        else: Map.delete(state.child_spawn_requests, tag)

    {:error, {:spawn_child_failed, reason}, %{state | child_spawn_requests: requests}}
  end

  defp complete(operation, {:uncertain, reason}, state),
    do: {:error, {:child_operation_indeterminate, operation.kind, reason}, state}

  defp complete(_operation, {:error, reason}, state), do: {:error, reason, state}

  defp resolve_child(pid, _operation) when is_pid(pid) do
    with :ok <- Jido.AgentServer.Liveness.check(pid, :child_not_alive), do: {:ok, pid}
  end

  defp resolve_child(id, %{jido: jido, partition: partition})
       when is_binary(id) and is_atom(jido) and not is_nil(jido) do
    case Server.whereis(Jido.registry_name(jido), id, partition: partition) do
      nil -> {:error, :child_not_found}
      pid -> {:ok, pid}
    end
  end

  defp resolve_child(value, _operation), do: {:error, {:invalid_child, value}}

  defp prepare_spawn(directive, cause, state) do
    target = directive.node || node()
    normalized = %{directive | node: target}

    case Map.get(state.child_spawn_requests, directive.tag) do
      %{directive: ^normalized, request_id: request, creation_cause: original_cause} ->
        {:ok, request, original_cause, state}

      %{request_id: request, directive: pending} ->
        {:error, {:child_spawn_pending, directive.tag, pending.node, request}}

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

  @doc false
  def verify_spawned_agent(
        info,
        directive,
        child_id,
        child_partition,
        parent_pid,
        parent_id
      )
      when is_map(info) do
    expected_module = expected_agent_module(directive.agent)
    parent = Map.get(info, :parent)

    mismatches =
      %{}
      |> mismatch(:id, child_id, Map.get(info, :agent_id))
      |> mismatch(:partition, child_partition, Map.get(info, :partition))
      |> mismatch(:module, expected_module, Map.get(info, :agent_module))
      |> mismatch(:parent_pid, parent_pid, parent_value(parent, :pid))
      |> mismatch(:parent_id, parent_id, parent_value(parent, :id))
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

  def verify_spawned_agent(
        info,
        directive,
        _child_id,
        _child_partition,
        _parent_pid,
        _parent_id
      ) do
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
end
