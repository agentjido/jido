defmodule Jido.AgentServer.TaskSupport do
  @moduledoc false

  alias Jido.Tracing.Context, as: TraceContext

  def task_ref?(%{task: %Task{ref: ref}}, ref), do: true
  def task_ref?(_pending, _ref), do: false

  def start_traced(jido, fun, timeout, tag) do
    trace = TraceContext.capture()

    task =
      Task.Supervisor.async(Jido.task_supervisor_name(jido), fn ->
        TraceContext.with_context(trace, fun)
      end)

    %{task: task, timer: start_task_timer(timeout, tag, task.ref)}
  end

  def release_task_result(%{task: %Task{ref: ref}, timer: timer}) do
    Process.demonitor(ref, [:flush])
    cancel_task_timer(timer)
  end

  def stop_task(%{task: %Task{} = task} = pending) do
    cancel_task_timer(Map.get(pending, :timer))
    shutdown_task(task)
  end

  def stop_task(nil), do: :ok

  def shutdown_task(%Task{} = task) do
    _result = Task.shutdown(task, :brutal_kill)
    :ok
  end

  def start_task_timer(:infinity, _tag, _task_ref), do: nil

  def start_task_timer(timeout, tag, task_ref) do
    :erlang.start_timer(timeout, self(), {tag, task_ref})
  end

  def cancel_task_timer(nil), do: :ok

  def cancel_task_timer(timer) do
    _result = :erlang.cancel_timer(timer)
    :ok
  end
end
