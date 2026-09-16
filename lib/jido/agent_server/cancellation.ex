defmodule Jido.AgentServer.Cancellation do
  @moduledoc false

  alias Jido.AgentServer.Idle
  alias Jido.AgentServer.TaskSupport
  alias Jido.AgentServer.TurnCompletion
  alias Jido.AgentServer.ActiveTurn
  alias Jido.AgentServer.ExecutionAdapter
  alias Jido.AgentServer.FailurePolicy
  alias Jido.AgentServer.State
  alias Jido.Error
  alias Jido.Tracing.Context, as: TraceContext

  def handle_event({:call, from}, :cancel, phase, %State{} = data)
      when phase in [:admitting, :running] do
    if phase == :admitting, do: cancel_admission(from, data), else: cancel_active(from, data)
  end

  def handle_event({:call, from}, :cancel, phase, %State{})
      when phase in [:initializing, :idle, :cancelling, :directing] do
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

  def handle_event({:call, from}, {:cancel, turn_id}, :cancelling, %State{active: active}) do
    reason = if active.turn_id == turn_id, do: :cancelling, else: :stale_turn
    {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
  end

  def handle_event({:call, from}, {:cancel, _turn_id}, phase, %State{})
      when phase in [:initializing, :idle, :admitting, :running, :directing] do
    {:keep_state_and_data, [{:reply, from, {:error, :stale_turn}}]}
  end

  def task_result(result, %State{cancel_task: pending} = data) do
    TaskSupport.release_task_result(pending)
    settle_cancel_result(result, %{data | cancel_task: nil}, pending)
  end

  def task_down(reason, %State{cancel_task: pending} = data) do
    TaskSupport.cancel_task_timer(pending.timer)
    error = cancellation_task_error(reason)
    settle_cancel_result({:error, error}, %{data | cancel_task: nil}, pending)
  end

  def task_timeout(%State{cancel_task: pending} = data) do
    TaskSupport.shutdown_task(pending.task)

    error =
      Error.timeout_error("Agent Exec cancellation task timed out",
        timeout: pending.timeout,
        details: %{code: :agent_exec_cancel_task_timeout}
      )

    settle_cancel_result({:error, error}, %{data | cancel_task: nil}, pending)
  end

  defp cancel_active(cancel_from, %State{active: %ActiveTurn{} = active} = data) do
    start_cancel_task(:user, cancel_from, active, data)
  end

  def start_cancel_task(mode, cancel_from, %ActiveTurn{} = active, %State{} = data) do
    if data.exec_module == Jido.Exec do
      result = cancel_exec(active.exec_handle, data)
      settle_cancel_result(result, data, %{mode: mode, from: cancel_from})
    else
      timeout = cancel_task_timeout(active.exec_handle, data)

      pending =
        TaskSupport.start_traced(
          data.jido,
          fn -> cancel_exec(active.exec_handle, data) end,
          timeout,
          :exec_cancel_timeout
        )
        |> Map.merge(%{timeout: timeout, from: cancel_from, mode: mode})

      {:next_state, :cancelling, %{data | cancel_task: pending}}
    end
  rescue
    error ->
      settle_cancel_result({:error, cancellation_task_error(error)}, data, %{
        mode: mode,
        from: cancel_from
      })
  catch
    kind, reason ->
      settle_cancel_result({:error, cancellation_task_error({kind, reason})}, data, %{
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
         %{mode: :user, from: cancel_from} = pending
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

      other ->
        settle_cancel_result(
          {:error, cancellation_task_error({:invalid_result, other})},
          data,
          pending
        )
    end
  end

  defp settle_timeout_cancel(:ok, %State{active: %ActiveTurn{} = active} = data) do
    stop_exec_adapter(active.exec_handle)
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

  defp settle_timeout_cancel(other, data),
    do: settle_timeout_cancel({:error, cancellation_task_error({:invalid_result, other})}, data)

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

  defp settle_parent_cancel(other, data, parent_reason),
    do:
      settle_parent_cancel(
        {:error, cancellation_task_error({:invalid_result, other})},
        data,
        parent_reason
      )

  defp cancel_task_timeout(%ExecutionAdapter{timeout: timeout}, _data), do: timeout + 100

  defp cancel_task_timeout(_handle, data), do: FailurePolicy.dispatch_timeout(data)

  defp cancellation_task_error(reason) do
    Error.execution_error("Agent Exec cancellation task failed",
      details: %{code: :agent_exec_cancel_task_failed, reason: reason}
    )
  end

  def timeout_admission(%State{active: %ActiveTurn{} = active} = data) do
    TaskSupport.stop_task(data.admission_task)
    data = %{data | admission_task: nil}
    TurnCompletion.fail_turn(turn_timeout_error(active), :prepare, data)
  end

  def timeout_execution(%State{active: %ActiveTurn{} = active} = data),
    do: start_cancel_task(:timeout, nil, active, data)

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

  def cancel_exec(%ExecutionAdapter{} = adapter, _data), do: ExecutionAdapter.cancel(adapter)
  def cancel_exec(handle, %State{} = data), do: data.exec_module.cancel(handle)

  def stop_exec_adapter(%ExecutionAdapter{} = adapter), do: ExecutionAdapter.stop(adapter)
  def stop_exec_adapter(_handle), do: :ok
end
