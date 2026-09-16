defmodule Jido.AgentServer.Cancellation do
  @moduledoc false

  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.TaskSupport
  alias Jido.AgentServer.TurnCompletion
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.State
  alias Jido.Error
  alias Jido.Tracing.Context, as: TraceContext

  def handle_event({:call, from}, :cancel, phase, %State{} = data)
      when phase in [:admitting, :running] do
    if phase == :admitting, do: cancel_admission(from, data), else: cancel_active(from, data)
  end

  def handle_event({:call, from}, :cancel, phase, %State{})
      when phase in [:initializing, :idle, :directing] do
    {:keep_state_and_data, [{:reply, from, {:error, phase}}]}
  end

  def handle_event(
        {:call, from},
        {:cancel, turn_id},
        phase,
        %State{active: %ActiveTurn{turn_id: turn_id}} = data
      )
      when phase in [:admitting, :running] do
    if phase == :admitting, do: cancel_admission(from, data), else: cancel_active(from, data)
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, phase, %State{})
      when phase in [:initializing, :idle, :admitting, :running, :directing] do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  defp cancel_active(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    cancel_execution(:user, cancel_from, active, data)
  end

  def cancel_execution(mode, cancel_from, %ActiveTurn{} = active, %State{} = data) do
    result = Jido.Exec.cancel(active.exec_handle)
    settle_cancel_result(result, data, %{mode: mode, from: cancel_from})
  rescue
    error ->
      settle_cancel_result({:error, cancellation_error(error)}, data, %{
        mode: mode,
        from: cancel_from
      })
  catch
    kind, reason ->
      settle_cancel_result({:error, cancellation_error({kind, reason})}, data, %{
        mode: mode,
        from: cancel_from
      })
  end

  defp settle_cancel_result(result, data, %{mode: :timeout}),
    do: settle_timeout_cancel(result, data)

  defp settle_cancel_result(result, data, %{mode: {:parent, parent_reason}}),
    do: settle_parent_cancel(result, data, parent_reason)

  defp settle_cancel_result(
         result,
         %State{active: %ActiveTurn{} = active} = data,
         %{mode: :user, from: cancel_from}
       ) do
    case result do
      :ok ->
        outcome = TurnCompletion.turn_outcome(data, :cancelled, :execute, :cancelled)

        next_data =
          data |> TurnCompletion.complete_outcome(outcome) |> Idle.maybe_start_idle_timer(:idle)

        TraceContext.clear()

        actions =
          TurnCompletion.reply_action(active.caller, {:error, :cancelled}) ++
            [{:reply, cancel_from, :ok}]

        {:next_state, :idle, next_data, actions}

      {:error, error} ->
        outcome = TurnCompletion.turn_outcome(data, :indeterminate, :execute, error)
        next_data = TurnCompletion.complete_outcome(data, outcome)
        TraceContext.clear()

        actions =
          TurnCompletion.reply_action(active.caller, {:error, error}) ++
            [{:reply, cancel_from, {:error, error}}]

        {:stop_and_reply, {:shutdown, {:exec_cancellation_failed, error}}, actions, next_data}
    end
  end

  defp settle_timeout_cancel(:ok, %State{active: %ActiveTurn{} = active} = data) do
    TurnCompletion.fail_turn(turn_timeout_error(active), :execute, data)
  end

  defp settle_timeout_cancel({:error, reason}, %State{active: %ActiveTurn{} = active} = data) do
    error = {:turn_timeout_cancellation_failed, reason}
    outcome = TurnCompletion.turn_outcome(data, :indeterminate, :execute, error)
    next_data = TurnCompletion.complete_outcome(data, outcome)
    TraceContext.clear()
    replies = TurnCompletion.reply_action(active.caller, {:error, error})

    if replies == [] do
      {:stop, {:shutdown, error}, next_data}
    else
      {:stop_and_reply, {:shutdown, error}, replies, next_data}
    end
  end

  defp settle_parent_cancel(:ok, %State{active: %ActiveTurn{} = active} = data, parent_reason) do
    error = {:parent_down, :cancelled}
    outcome = TurnCompletion.turn_outcome(data, :cancelled, :execute, error)
    replies = TurnCompletion.reply_action(active.caller, {:error, error})
    next_data = TurnCompletion.complete_outcome(data, outcome)
    TraceContext.clear()
    reason = {:shutdown, {:parent_down, parent_reason}}

    if replies == [],
      do: {:stop, reason, next_data},
      else: {:stop_and_reply, reason, replies, next_data}
  end

  defp settle_parent_cancel(
         {:error, reason},
         %State{active: %ActiveTurn{} = active} = data,
         _parent_reason
       ) do
    error = {:parent_down, {:cancellation_failed, reason}}
    outcome = TurnCompletion.turn_outcome(data, :indeterminate, :execute, error)
    replies = TurnCompletion.reply_action(active.caller, {:error, error})
    next_data = TurnCompletion.complete_outcome(data, outcome)
    TraceContext.clear()

    if replies == [],
      do: {:stop, {:shutdown, error}, next_data},
      else: {:stop_and_reply, {:shutdown, error}, replies, next_data}
  end

  defp cancellation_error(reason) do
    Error.execution_error("Agent Exec cancellation failed",
      details: %{code: :agent_exec_cancel_failed, reason: reason}
    )
  end

  def timeout_admission(%State{active: %ActiveTurn{} = active} = data) do
    TaskSupport.stop_task(data.admission_task)
    data = %{data | admission_task: nil}
    TurnCompletion.fail_turn(turn_timeout_error(active), :prepare, data)
  end

  def timeout_execution(%State{active: %ActiveTurn{} = active} = data),
    do: cancel_execution(:timeout, nil, active, data)

  defp turn_timeout_error(%ActiveTurn{} = active) do
    Error.timeout_error("Agent Turn timed out",
      timeout: active.timeout,
      details: %{code: :agent_turn_timeout, turn_id: active.turn_id}
    )
  end

  defp cancel_admission(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    TaskSupport.stop_task(data.admission_task)
    outcome = TurnCompletion.turn_outcome(data, :cancelled, :prepare, :cancelled)

    next_data =
      data
      |> Map.put(:admission_task, nil)
      |> TurnCompletion.complete_outcome(outcome)
      |> Idle.maybe_start_idle_timer(:idle)

    TraceContext.clear()

    actions =
      TurnCompletion.reply_action(active.caller, {:error, :cancelled}) ++
        [{:reply, cancel_from, :ok}]

    {:next_state, :idle, next_data, actions}
  end
end
