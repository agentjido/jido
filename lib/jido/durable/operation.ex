defmodule Jido.Durable.Operation do
  @moduledoc false

  alias Jido.Durable.{Execution, Ref, Runtime, Status}
  alias Jido.Error
  alias Jido.Instance.Names
  alias Jido.Persistence.ContinuationStore

  @max_receive_timeout 4_294_967_295

  def valid_timeout?(:infinity), do: true
  def valid_timeout?(ms), do: is_integer(ms) and ms in 0..@max_receive_timeout

  def with_owner(ref, opts, work) do
    deadline = deadline(Ref.execution_id(ref), Keyword.get(opts, :operation_timeout, :infinity))
    lock = {{__MODULE__, ref}, make_ref()}

    operation = fn ->
      with :ok <- check_deadline(deadline),
           {:ok, status} <- work.(deadline),
           :ok <- check_deadline(deadline),
           do: {:ok, status}
    end

    case :global.trans(lock, operation, [node()], 0) do
      :aborted -> {:error, :execution_busy}
      result -> result
    end
  end

  def execute(jido, %Execution{} = execution, config, opts, deadline) do
    with :ok <- check_deadline(deadline), do: execute_owned(jido, execution, config, opts, deadline)
  end

  defp execute_owned(jido, execution, config, opts, deadline) do
    runner = Names.exec_runner(jido)
    id = Ref.execution_id(execution.ref)
    notification = :erlang.alias()

    open_opts = [
      instance: jido,
      persistence: config,
      policy: Runtime.execution_policy(execution.exec_opts),
      max_concurrency: Keyword.get(execution.exec_opts, :max_concurrency, 1),
      now: Keyword.get(opts, :now, System.system_time(:millisecond)),
      notify: fn -> send(notification, {__MODULE__, notification}) end
    ]

    try do
      result = open_and_advance(runner, id, execution, open_opts, deadline, notification)

      with :ok <- Runtime.cancel(runner, id),
           :ok <- result,
           {:ok, workflow} <- ContinuationStore.read_workflow(config, id) do
        {:ok, Status.new(execution.ref, workflow)}
      end
    after
      :erlang.unalias(notification)
      flush_progress(notification)
    end
  end

  defp open_and_advance(runner, id, execution, opts, deadline, notification) do
    case Runtime.open(runner, id, execution.instruction, execution.context, opts) do
      {:ok, worker, ^id} ->
        monitor = Process.monitor(worker)

        try do
          advance(runner, id, deadline, notification, monitor)
        after
          Process.demonitor(monitor, [:flush])
        end

      {:waiting, _waits, _next_wake_at} ->
        :ok

      {:error, _reason} = error ->
        error
    end
  catch
    :exit, reason -> worker_exit(reason)
  end

  defp advance(runner, id, deadline, notification, monitor) do
    check = fn -> check_deadline(deadline) end

    with :ok <- check.() do
      case Runtime.advance(runner, id, check) do
        :running ->
          receive do
            {__MODULE__, ^notification} -> advance(runner, id, deadline, notification, monitor)
            {:DOWN, ^monitor, :process, _pid, reason} -> worker_exit(reason)
          after
            remaining(deadline) -> timeout_error(deadline)
          end

        :complete ->
          :ok

        {:waiting, _waits, _next_wake_at} ->
          :ok

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp deadline(id, :infinity), do: {id, :infinity}
  defp deadline(id, ms), do: {id, System.monotonic_time(:millisecond) + ms}
  defp remaining({_id, :infinity}), do: :infinity
  defp remaining({_id, expires_at}), do: max(expires_at - System.monotonic_time(:millisecond), 0)

  defp check_deadline(deadline) do
    if remaining(deadline) == 0, do: timeout_error(deadline), else: :ok
  end

  defp timeout_error({id, _expires_at}) do
    {:error,
     Error.execution_error("durable execution did not reach a stop before timeout", %{
       execution_id: id,
       reason: :timeout,
       retry: true
     })}
  end

  defp worker_exit(reason) do
    {:error, Error.execution_error("durable execution worker exited", %{reason: reason})}
  end

  defp flush_progress(notification) do
    receive do
      {__MODULE__, ^notification} -> flush_progress(notification)
    after
      0 -> :ok
    end
  end
end
