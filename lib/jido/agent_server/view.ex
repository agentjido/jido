defmodule Jido.AgentServer.View do
  @moduledoc false

  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.{ActiveTurn, ChildInfo, ParentRef, State}
  alias Jido.Error

  @doc false
  @spec status(atom(), State.t(), non_neg_integer()) :: map()
  def status(phase, %State{} = data, message_queue_len) do
    %{
      phase: phase,
      agent_id: data.agent.id,
      state_version: data.state_version,
      admission: %{
        postponed: MapSet.size(data.postponed_tokens),
        limit: data.max_postponed_signals,
        message_queue_len: message_queue_len
      },
      runtime: %{
        partition: data.partition,
        parent: parent(data.parent),
        child_count: map_size(data.children),
        pending_child_spawns: pending_child_spawns(data.child_spawn_requests),
        error_count: data.error_count,
        lifecycle: %{
          pool: data.pool,
          attached: map_size(data.attachments),
          idle_timeout: data.idle_timeout,
          idle_timer?: not is_nil(data.idle_timer)
        }
      },
      active: active(data.active)
    }
  end

  @doc false
  @spec children(State.t()) :: map()
  def children(%State{} = data) do
    Map.new(data.children, fn {key, child} -> {key, child(child)} end)
  end

  @doc false
  @spec relationship_info(State.t()) :: map()
  def relationship_info(%State{} = data) do
    %{
      agent_id: data.agent.id,
      agent_module: data.agent.module,
      partition: data.partition,
      parent: parent(data.parent)
    }
  end

  @doc false
  @spec outcome_summary(Outcome.t()) :: map()
  def outcome_summary(%Outcome{} = outcome) do
    signal = outcome.effective_signal || outcome.source_signal

    %{
      id: outcome.id,
      agent_id: outcome.agent_id,
      signal_id: signal.id,
      signal_type: signal.type,
      status: outcome.status,
      stage: outcome.stage,
      committed?: outcome.committed?,
      state_version_before: outcome.state_version_before,
      state_version_after: outcome.state_version_after,
      directives: outcome.directives,
      started_at: outcome.started_at,
      finished_at: outcome.finished_at,
      duration_ms: outcome.duration_ms,
      error: if(outcome.error, do: Error.to_map(outcome.error))
    }
  end

  defp active(nil), do: nil

  defp active(%ActiveTurn{} = active) do
    signal = active.effective_signal || active.source_signal

    %{
      turn_id: active.turn_id,
      source_signal_id: active.source_signal.id,
      signal_id: signal.id,
      signal_type: signal.type,
      start_version: active.start_version,
      committed_version: active.committed_version
    }
  end

  defp pending_child_spawns(requests) do
    for {tag, %{status: :pending} = request} <- requests, into: %{} do
      {tag, %{node: request.directive.node, request_id: request.request_id}}
    end
  end

  defp child(%ChildInfo{} = child) do
    %{
      pid: child.pid,
      module: child.module,
      id: child.id,
      partition: child.partition,
      tag: child.tag,
      kind: child.kind,
      meta: child.meta
    }
  end

  defp parent(nil), do: nil

  defp parent(%ParentRef{} = parent) do
    %{
      pid: parent.pid,
      id: parent.id,
      partition: parent.partition,
      tag: parent.tag,
      spawn_ref: parent.spawn_ref,
      meta: parent.meta
    }
  end
end
