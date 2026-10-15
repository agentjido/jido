defmodule Jido.AgentServer.Execution do
  @moduledoc false

  alias Jido.AgentServer.{ActiveTurn, Cancellation, TaskSupport, Turn, TurnCompletion}

  def start(prepared, data) do
    owner = self()
    id = data.active.turn_id
    runner = Jido.exec_runner_name(data.jido)

    opts =
      Keyword.merge(prepared.exec_opts,
        mode: :local,
        owner: owner,
        max_concurrency: Keyword.get(prepared.exec_opts, :max_concurrency, 1),
        on_complete: fn ^id, _workflow -> send(owner, {:exec_settled, id}) end
      )

    handle = %{runner: runner, id: id, pid: nil, ref: nil}
    data = %{data | active: ActiveTurn.begin_execution(data.active, handle, prepared)}

    operation(data, :start, fn ->
      Jido.Exec.start(
        runner,
        id,
        prepared.turn.executable,
        prepared.turn.input,
        prepared.context,
        opts
      )
    end)
  end

  def settled(id, %{active: %{turn_id: id}, execution_task: %{kind: :start}}),
    do: {:keep_state_and_data, [:postpone]}

  def settled(
        id,
        %{active: %{turn_id: id, cancel_request: nil, exec_handle: %{}}, execution_task: nil} =
          data
      ) do
    handle = data.active.exec_handle

    operation(data, :settle, fn ->
      result = Jido.Exec.result(handle.runner, handle.id)
      {result, Runic.Runner.cancel(handle.runner, handle.id)}
    end)
  end

  def settled(_id, _data), do: :keep_state_and_data

  def result(result, %{execution_task: pending} = data) do
    TaskSupport.stop_task(pending)
    data = %{data | execution_task: nil}
    complete(pending.kind, result, data)
  end

  defp complete(:start, {:ok, pid}, data) do
    handle = %{data.active.exec_handle | pid: pid, ref: Process.monitor(pid)}
    data = %{data | active: %{data.active | exec_handle: handle}}

    cond do
      data.active.cancel_request -> cancel_worker(data)
      ActiveTurn.expired?(data.active) -> cancel(:timeout, nil, data.active, data)
      true -> {:next_state, :running, data}
    end
  end

  defp complete(:start, {:error, reason}, data) do
    if data.active.cancel_request,
      do: Cancellation.settle_cancel_result(:ok, clear_handle(data), data.active.cancel_request),
      else: TurnCompletion.fail_turn(reason, :prepare, clear_handle(data))
  end

  defp complete(:settle, {result, cleanup}, data) do
    data = clear_handle(data)

    cond do
      data.active.cancel_request ->
        Cancellation.settle_cancel_result(cleanup, data, data.active.cancel_request)

      cleanup != :ok ->
        Cancellation.settle_cancel_result(cleanup, data, %{mode: :user, from: nil})

      true ->
        Turn.finish_turn(result, data)
    end
  end

  defp complete(:cancel, result, data),
    do: Cancellation.settle_cancel_result(result, clear_handle(data), data.active.cancel_request)

  def cancel(mode, from, active, data) do
    cond do
      active.cancel_request && match?({:parent, _}, mode) ->
        request = %{active.cancel_request | mode: mode}
        {:keep_state, %{data | active: %{active | cancel_request: request}}}

      active.cancel_request ->
        {:keep_state_and_data, TurnCompletion.reply_action(from, {:error, :cancelling})}

      is_nil(active.exec_handle) ->
        Cancellation.settle_cancel_result(:ok, data, %{mode: mode, from: from})

      true ->
        data = %{data | active: %{active | cancel_request: %{mode: mode, from: from}}}

        if data.execution_task,
          do: {:next_state, :cancelling, data},
          else: cancel_worker(data)
    end
  end

  defp cancel_worker(data) do
    handle = data.active.exec_handle
    operation(data, :cancel, fn -> Runic.Runner.cancel(handle.runner, handle.id) end)
  end

  def down(reason, %{execution_task: pending} = data) do
    TaskSupport.cancel_task_timer(pending.timer)

    fail_owner(reason, %{data | execution_task: nil})
  end

  def message({:DOWN, ref, :process, _pid, reason}, %{active: %{exec_handle: %{ref: ref}}} = data) do
    if data.execution_task, do: :keep_state_and_data, else: fail_owner(reason, data)
  end

  def message(_message, _data), do: :keep_state_and_data

  defp operation(data, kind, fun) do
    pending =
      Map.put(TaskSupport.start_traced(data.jido, fun, :infinity, :execution), :kind, kind)

    phase = %{start: :starting, settle: :settling, cancel: :cancelling}[kind]
    {:next_state, phase, %{data | execution_task: pending}}
  rescue
    error -> operation_failed(kind, error, data)
  catch
    exit_kind, reason -> operation_failed(kind, {exit_kind, reason}, data)
  end

  defp operation_failed(:start, reason, data),
    do: TurnCompletion.fail_turn(operation_error(reason), :prepare, clear_handle(data))

  defp operation_failed(_kind, reason, data), do: fail_owner(reason, data)

  defp fail_owner(reason, data) do
    error = operation_error(reason)
    outcome = TurnCompletion.turn_outcome(data, :indeterminate, :execute, error)
    request = data.active.cancel_request

    replies =
      TurnCompletion.reply_action(data.active.caller, {:error, error}) ++
        TurnCompletion.reply_action(request && request.from, {:error, error})

    TurnCompletion.stop(
      TurnCompletion.complete_outcome(data, outcome),
      {:exec_cancellation_failed, error},
      replies
    )
  end

  defp operation_error(reason),
    do: Jido.Error.execution_error("Owned execution lifecycle failed", details: %{reason: reason})

  defp clear_handle(data) do
    if data.active.exec_handle && data.active.exec_handle.ref,
      do: Process.demonitor(data.active.exec_handle.ref, [:flush])

    %{data | active: %{data.active | exec_handle: nil}}
  end
end
