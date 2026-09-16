defmodule Jido.AgentServer.TurnCompletion do
  @moduledoc false

  alias Jido.AgentServer.Idle
  require Logger
  alias Jido.Agent.Turn.Outcome
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.FailurePolicy
  alias Jido.AgentServer.Inspection
  alias Jido.AgentServer.Shutdown
  alias Jido.AgentServer.State
  alias Jido.Error
  alias Jido.Telemetry.Agent, as: AgentTelemetry
  alias Jido.Tracing.Context, as: TraceContext

  def fail_turn(reason, stage, %State{active: %ActiveTurn{} = active} = data) do
    signal = active.effective_signal || active.source_signal
    maybe_log_cast_failure(active.caller, signal, reason, data.agent.id)
    outcome = turn_outcome(data, outcome_status(reason), stage, reason)

    next_data =
      data
      |> Map.update!(:error_count, &(&1 + 1))
      |> complete_outcome(outcome)

    TraceContext.clear()

    decision =
      case reason do
        {:persistence_failed, failure} ->
          {:stop, {:shutdown, {:persistence_failed, failure}}, next_data}

        _reason ->
          FailurePolicy.decide(outcome, next_data)
      end

    case decision do
      {:continue, policy_data} ->
        {:next_state, :idle, Idle.maybe_start_idle_timer(policy_data, :idle),
         reply_action(active.caller, {:error, reason})}

      {:stop, stop_reason, policy_data} ->
        replies = reply_action(active.caller, {:error, reason})
        stop_reason = Shutdown.normalize_reason(stop_reason)

        if replies == [] do
          {:stop, stop_reason, policy_data}
        else
          {:stop_and_reply, stop_reason, replies, policy_data}
        end
    end
  end

  defp maybe_log_cast_failure(nil, signal, reason, agent_id) do
    Logger.error("Agent Signal cast failed",
      agent_id: agent_id,
      signal_id: signal.id,
      signal_type: signal.type,
      reason: inspect(reason)
    )
  end

  defp maybe_log_cast_failure(_from, _signal, _reason, _agent_id), do: :ok

  def apply_post_commit_error_policy(%Outcome{} = outcome, data) do
    next_data = %{data | error_count: data.error_count + 1}

    case FailurePolicy.decide(outcome, next_data) do
      {:continue, policy_data} ->
        TraceContext.clear()
        {:next_state, :idle, Idle.maybe_start_idle_timer(policy_data, :idle)}

      {:stop, stop_reason, policy_data} ->
        {:stop, {:shutdown, stop_reason}, policy_data}
    end
  end

  def turn_outcome(%State{active: active, agent: agent}, status, stage, error),
    do: ActiveTurn.outcome(active, agent.id, status, stage, error)

  def complete_outcome(%State{} = data, %Outcome{} = outcome) do
    if data.active, do: ActiveTurn.cancel_timeout(data.active)
    AgentTelemetry.settled(data, outcome)
    signal = outcome.effective_signal || outcome.source_signal
    event = if outcome.status == :succeeded, do: :turn_completed, else: :turn_failed

    data
    |> Map.put(:active, nil)
    |> then(fn data ->
      if outcome.status == :succeeded, do: %{data | error_count: 0}, else: data
    end)
    |> Inspection.record_event(event, %{
      turn_id: outcome.id,
      signal_id: signal.id,
      signal_type: signal.type,
      stage: outcome.stage,
      error: if(outcome.error, do: Inspection.public_error(outcome.error)),
      outcome: Inspection.outcome_summary(outcome)
    })
  end

  def outcome_status({:child_spawn_indeterminate, _tag, _node, _request, _reason}),
    do: :indeterminate

  def outcome_status(reason) do
    case Error.to_map(reason) do
      %{type: :timeout} -> :timed_out
      _error -> :failed
    end
  end

  def reply_action(nil, _reply), do: []
  def reply_action(from, reply), do: [{:reply, from, reply}]
end
