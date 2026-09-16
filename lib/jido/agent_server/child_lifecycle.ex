defmodule Jido.AgentServer.ChildLifecycle do
  @moduledoc false

  alias Jido.AgentServer.Cancellation
  alias Jido.AgentServer.Shutdown

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.Signal.{ChildExit, Orphaned}

  alias Jido.AgentServer.{
    ChildInfo,
    ChildOperations,
    ChildPlacement,
    Inspection,
    Options,
    ParentRef,
    Relationship,
    State
  }

  def attach_parent(%State{parent: %ParentRef{}}, _parent), do: {:error, :already_has_parent}

  def attach_parent(%State{} = data, %ParentRef{pid: pid} = parent) do
    cond do
      pid == self() ->
        {:error, :cannot_adopt_self}

      not is_pid(pid) or not Process.alive?(pid) ->
        {:error, :parent_not_alive}

      true ->
        monitored = %{parent | ref: Process.monitor(pid)}
        next_data = %{data | parent: monitored, orphaned_from: nil}

        case Relationship.put_own(next_data) do
          :ok ->
            {:ok, next_data}

          {:error, reason} ->
            Process.demonitor(monitored.ref, [:flush])
            {:error, {:relationship_persist_failed, reason}}
        end
    end
  end

  def monitor_parent(nil), do: nil

  def monitor_parent(%ParentRef{pid: pid} = parent) when is_pid(pid) do
    %{parent | ref: Process.monitor(pid)}
  end

  def restore_parent(%Options{parent: %ParentRef{} = parent}, _agent), do: parent

  def restore_parent(%Options{jido: jido, partition: partition}, agent)
      when is_atom(jido) and not is_nil(jido) do
    with {:ok, binding} <- Jido.agent_parent_binding(jido, agent.id, partition: partition),
         parent_pid when is_pid(parent_pid) <-
           Server.whereis(Jido.registry_name(jido), binding.parent_id,
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

  def restore_parent(%Options{}, _agent), do: nil

  def notify_parent_online(%State{parent: %ParentRef{} = parent} = data) do
    send(
      parent.pid,
      {:agent_child_online, self(), data.agent.id, data.agent.module, data.partition, parent.tag,
       parent.meta}
    )

    :ok
  end

  def notify_parent_online(%State{}), do: :ok

  def verify_child_online(pid, child_id, tag, %State{} = data) do
    case Server.creation_info(pid) do
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
               ChildOperations.verify_spawned_agent(
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
        :ok

      nil ->
        {:error, :unknown_remote_child, :stop}
    end
  end

  def track_online_child(data, pid, info) do
    tag = info.parent.tag
    meta = info.parent.meta

    case State.child(data, tag) do
      %ChildInfo{pid: ^pid} ->
        State.mark_spawn_active(data, tag)

      existing ->
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

        case Relationship.put_child(data, child) do
          :ok ->
            if match?(%ChildInfo{}, existing), do: Process.demonitor(existing.ref, [:flush])

            signal =
              Jido.AgentServer.Signal.ChildStarted.for_child(
                data.agent.id,
                child,
                not is_nil(existing)
              )

            Server.cast(self(), signal)
            data |> State.mark_spawn_active(tag) |> State.add_child(tag, child)

          {:error, _reason} ->
            Process.demonitor(child.ref, [:flush])

            _ =
              ChildPlacement.stop(
                data.jido,
                pid,
                :relationship_persist_failed,
                data.directive_timeout
              )

            data
        end
    end
  end

  def relationship_info(%State{} = data) do
    %{
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      partition: data.partition,
      parent: Inspection.parent(data.parent)
    }
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

      {:error, _reason, :stop} ->
        _ = ChildPlacement.stop(data.jido, pid, :identity_mismatch, data.directive_timeout)
        :keep_state_and_data

      {:error, _reason} ->
        :keep_state_and_data
    end
  end

  def handle_child_down({key, %ChildInfo{kind: :plugin} = child}, pid, reason, data) do
    next_data = State.remove_child(data, key)
    {:stop, {:plugin_runtime_down, child.module, pid, reason}, next_data}
  end

  def handle_child_down({key, %ChildInfo{} = child}, pid, reason, data) do
    next_data = State.remove_child(data, key)

    next_data =
      if Shutdown.clean?(reason) do
        _ = Relationship.delete_child(data, child)
        %{next_data | child_spawn_requests: Map.delete(next_data.child_spawn_requests, key)}
      else
        next_data
      end

    signal =
      ChildExit.new!(
        %{tag: child.tag, child_id: child.id, pid: pid, reason: reason},
        source: "/agent/#{data.agent.id}"
      )

    Server.cast(self(), signal)
    {:keep_state, next_data}
  end

  def handle_parent_down(reason, %State{parent: %ParentRef{} = parent} = data) do
    next_data = %{data | parent: nil, orphaned_from: parent}
    _ = Relationship.delete_own(next_data)

    case data.on_parent_death do
      :stop ->
        case next_data.active do
          %ActiveTurn{exec_handle: handle} = active when not is_nil(handle) ->
            Cancellation.start_cancel_task({:parent, reason}, nil, active, next_data)

          _inactive ->
            {:stop, {:shutdown, {:parent_down, reason}}, next_data}
        end

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

        Server.cast(self(), signal)
        {:keep_state, next_data}
    end
  end

  def retire_remote_spawn(reason, %State{parent: %ParentRef{spawn_ref: request}, jido: jido})
      when not is_nil(request) and not is_nil(jido) do
    if Shutdown.clean?(reason), do: Jido.AgentServer.SpawnRegistry.retire(jido, self())
    :ok
  catch
    :exit, _ -> :ok
  end

  def retire_remote_spawn(_reason, _data), do: :ok
end
