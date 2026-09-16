defmodule Jido.AgentServer.Inspection do
  @moduledoc false

  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.{ActiveTurn, ChildInfo, ParentRef, State}
  alias Jido.Error

  def status(phase, %State{} = data) do
    message_queue_len =
      case Process.info(self(), :message_queue_len) do
        {:message_queue_len, length} -> length
        nil -> 0
      end

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
        pending_child_spawns: pending_child_spawns(data),
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

  def child(%ChildInfo{} = child) do
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

  def parent(nil), do: nil

  def parent(%ParentRef{} = parent) do
    %{
      pid: parent.pid,
      id: parent.id,
      partition: parent.partition,
      tag: parent.tag,
      spawn_ref: parent.spawn_ref,
      meta: parent.meta
    }
  end

  def record_event(%State{debug: false} = data, _event, _metadata), do: data

  def record_event(%State{} = data, event, metadata) do
    entry = %{event: event, at: System.system_time(:millisecond), metadata: metadata}
    events = Enum.take([entry | data.debug_events], data.debug_max_events)
    %{data | debug_events: events}
  end

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
      error: if(outcome.error, do: public_error(outcome.error))
    }
  end

  def public_error(reason), do: Error.to_map(reason)

  defp normalize_event_limit(limit) when is_integer(limit) and limit >= 0, do: limit
  defp normalize_event_limit(_limit), do: 0

  defp pending_child_spawns(data) do
    for {tag, %{status: :pending} = request} <- data.child_spawn_requests, into: %{} do
      {tag, %{node: request.directive.node, request_id: request.request_id}}
    end
  end

  def recent_events(%State{} = data, opts) do
    if data.debug do
      limit = opts |> Keyword.get(:limit, data.debug_max_events) |> normalize_event_limit()
      {:ok, Enum.take(data.debug_events, limit)}
    else
      {:error, :debug_not_enabled}
    end
  end
end
