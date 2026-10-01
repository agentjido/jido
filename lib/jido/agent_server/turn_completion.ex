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
        return_idle(policy_data, reply_action(active.caller, {:error, reason}))

      {:stop, stop_reason, policy_data} ->
        stop(policy_data, stop_reason, reply_action(active.caller, {:error, reason}))
    end
  end

  defp maybe_log_cast_failure(nil, signal, reason, agent_id) do
    Logger.error("Agent Signal cast failed",
      agent_id: agent_id,
      signal_id: signal.id,
      signal_type: signal.type,
      reason: inspect(Jido.Error.to_map(reason))
    )
  end

  defp maybe_log_cast_failure(_from, _signal, _reason, _agent_id), do: :ok

  def apply_post_commit_error_policy(%Outcome{} = outcome, data) do
    next_data = %{data | error_count: data.error_count + 1}

    case FailurePolicy.decide(outcome, next_data) do
      {:continue, policy_data} ->
        return_idle(policy_data)

      {:stop, stop_reason, policy_data} ->
        stop(policy_data, stop_reason)
    end
  end

  def succeed(data, stage, actions \\ []) do
    outcome = turn_outcome(data, :succeeded, stage, nil)
    data |> complete_outcome(outcome) |> return_idle(actions)
  end

  def return_idle(data, actions \\ []) do
    TraceContext.clear()
    {:next_state, :idle, Idle.maybe_start_idle_timer(data, :idle), actions}
  end

  def stop(data, reason, replies \\ []) do
    reason = Shutdown.normalize_reason(reason)
    if replies == [], do: {:stop, reason, data}, else: {:stop_and_reply, reason, replies, data}
  end

  def turn_outcome(%State{active: active, agent: agent}, status, stage, error),
    do: ActiveTurn.outcome(active, agent.id, status, stage, error)

  def complete_outcome(%State{} = data, %Outcome{} = outcome) do
    if data.active, do: ActiveTurn.cancel_timeout(data.active)
    AgentTelemetry.settled(data, outcome)
    event = if outcome.status == :succeeded, do: :turn_completed, else: :turn_failed

    data
    |> Map.put(:active, nil)
    |> then(fn data ->
      if outcome.status == :succeeded, do: %{data | error_count: 0}, else: data
    end)
    |> Inspection.record_event(event, fn ->
      summary = Inspection.outcome_summary(outcome)

      %{
        turn_id: outcome.id,
        signal_id: summary.signal_id,
        signal_type: summary.signal_type,
        stage: outcome.stage,
        error: summary.error,
        outcome: summary
      }
    end)
  end

  def outcome_status({:child_spawn_indeterminate, _tag, _node, _request, _reason}),
    do: :indeterminate

  def outcome_status({:child_operation_indeterminate, _kind, _reason}), do: :indeterminate

  def outcome_status(reason) do
    case Error.to_map(reason) do
      %{type: :timeout} -> :timed_out
      _error -> :failed
    end
  end

  def reply_action(nil, _reply), do: []
  def reply_action(from, reply), do: [{:reply, from, reply}]
end
