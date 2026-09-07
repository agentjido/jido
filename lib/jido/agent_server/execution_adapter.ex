defmodule Jido.AgentServer.ExecutionAdapter do
  @moduledoc false

  alias Jido.Error

  @fallback_timeout 5_000

  defstruct [
    :pid,
    :monitor_ref,
    :ref,
    :module,
    :exec_pid,
    :callback_token,
    :timer,
    :timeout
  ]

  @type t :: %__MODULE__{}

  @doc false
  def start(owner, supervisor, module, args, timeout) do
    ref = make_ref()
    timeout = finite_timeout(timeout)

    case Task.Supervisor.start_child(supervisor, fn -> run(owner, ref, module, args) end) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)
        timer = start_timer(timeout, ref, :startup, :run_async)

        {:ok,
         %__MODULE__{
           pid: pid,
           monitor_ref: monitor_ref,
           ref: ref,
           module: module,
           callback_token: :startup,
           timer: timer,
           timeout: timeout
         }}

      {:error, reason} ->
        {:error,
         Error.execution_error("Agent Exec adapter owner could not start",
           details: %{module: module, reason: reason}
         )}
    end
  rescue
    error -> {:error, callback_error(module, :run_async, :error, error)}
  catch
    kind, reason -> {:error, callback_error(module, :run_async, kind, reason)}
  end

  @doc false
  def forward(%__MODULE__{pid: pid, ref: ref}, message) when is_pid(pid) do
    send(pid, {:jido_exec_adapter_forward, ref, message})
    :ok
  end

  @doc false
  def cancel(%__MODULE__{} = adapter) do
    request_ref = make_ref()
    monitor_ref = Process.monitor(adapter.pid)
    send(adapter.pid, {:jido_exec_adapter_cancel, adapter.ref, self(), request_ref})

    receive do
      {:jido_exec_adapter_cancelled, ^request_ref, result} ->
        Process.demonitor(monitor_ref, [:flush])
        result

      {:DOWN, ^monitor_ref, :process, _pid, reason} ->
        {:error,
         Error.execution_error("Agent Exec adapter owner exited during cancellation",
           details: %{module: adapter.module, reason: reason}
         )}
    after
      adapter.timeout ->
        Process.demonitor(monitor_ref, [:flush])
        stop(adapter)

        {:error,
         Error.timeout_error("Agent Exec cancellation timed out",
           timeout: adapter.timeout,
           details: %{module: adapter.module}
         )}
    end
  end

  @doc false
  def stop(%__MODULE__{pid: pid, monitor_ref: ref}) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :kill)
    :ok
  end

  @doc false
  def callback_started(%__MODULE__{} = adapter, token, callback) do
    cancel_timer(adapter.timer)

    %{
      adapter
      | callback_token: token,
        timer: start_timer(adapter.timeout, adapter.ref, token, callback)
    }
  end

  @doc false
  def callback_finished(%__MODULE__{} = adapter, token) do
    if adapter.callback_token == token do
      cancel_timer(adapter.timer)
      %{adapter | callback_token: nil, timer: nil}
    else
      adapter
    end
  end

  @doc false
  def started(%__MODULE__{} = adapter, exec_pid) do
    adapter
    |> callback_finished(:startup)
    |> Map.put(:exec_pid, exec_pid)
  end

  @doc false
  def acknowledge(%__MODULE__{pid: pid, ref: ref}, token) do
    send(pid, {:jido_exec_adapter_ack, ref, token})
    :ok
  end

  @doc false
  def timeout?(%__MODULE__{} = adapter, timer, token) do
    adapter.timer == timer and adapter.callback_token == token
  end

  @doc false
  def cancel_timer(%__MODULE__{timer: timer}), do: cancel_timer(timer)
  def cancel_timer(nil), do: :ok

  def cancel_timer(timer) do
    _ = :erlang.cancel_timer(timer)
    :ok
  end

  defp run(owner, ref, module, args) do
    Process.link(owner)

    with {:ok, handle} <- invoke(module, :run_async, args),
         {:ok, exec_pid} <- validate_handle(handle, module) do
      if Process.alive?(exec_pid), do: Process.link(exec_pid)
      send(owner, {:jido_exec_adapter_started, ref, exec_pid})
      loop(owner, ref, module, handle)
    else
      {:error, error} ->
        send(owner, {:jido_exec_adapter_start_failed, ref, error})
    end
  end

  defp loop(owner, ref, module, handle) do
    receive do
      {:jido_exec_adapter_forward, ^ref, message} ->
        handle_message(owner, ref, module, handle, message)

      {:jido_exec_adapter_cancel, ^ref, requester, request_ref} ->
        result = normalize_cancel(invoke(module, :cancel, [handle]), module)
        send(requester, {:jido_exec_adapter_cancelled, request_ref, result})

        if result == :ok do
          stop_handle(handle)
        else
          loop(owner, ref, module, handle)
        end

      message ->
        handle_message(owner, ref, module, handle, message)
    end
  end

  defp handle_message(owner, ref, module, handle, message) do
    token = make_ref()
    send(owner, {:jido_exec_adapter_callback_started, ref, token, :handle_message})

    result =
      module
      |> invoke(:handle_message, [handle, message])
      |> normalize_handle_message(module)

    send(owner, {:jido_exec_adapter_callback_result, ref, token, result})

    if result == :ignore do
      loop(owner, ref, module, handle)
    else
      await_terminal_ack(owner, ref, token, module, handle)
    end
  end

  defp await_terminal_ack(owner, ref, token, module, handle) do
    receive do
      {:jido_exec_adapter_ack, ^ref, ^token} ->
        stop_handle(handle)

      {:jido_exec_adapter_cancel, ^ref, requester, request_ref} ->
        result = normalize_cancel(invoke(module, :cancel, [handle]), module)
        send(requester, {:jido_exec_adapter_cancelled, request_ref, result})

        if result == :ok do
          stop_handle(handle)
        else
          await_terminal_ack(owner, ref, token, module, handle)
        end

      _message ->
        await_terminal_ack(owner, ref, token, module, handle)
    end
  end

  defp validate_handle(%Task{pid: pid}, _module) when is_pid(pid), do: {:ok, pid}

  defp validate_handle(%{pid: pid, owner: owner}, _module)
       when is_pid(pid) and owner == self(),
       do: {:ok, pid}

  defp validate_handle(%{pid: pid}, _module) when is_pid(pid) do
    if Process.alive?(pid), do: {:ok, pid}, else: {:error, invalid_handle_error(pid)}
  end

  defp validate_handle(handle, module) do
    {:error,
     Error.execution_error("Agent Exec run_async returned an invalid handle",
       details: %{module: module, handle: inspect(handle)}
     )}
  end

  defp invalid_handle_error(pid) do
    Error.execution_error("Agent Exec run_async returned a dead process handle",
      details: %{pid: inspect(pid)}
    )
  end

  defp normalize_handle_message({:ok, :ignore}, _module), do: :ignore
  defp normalize_handle_message({:ok, {:done, _value} = result}, _module), do: result
  defp normalize_handle_message({:ok, {:error, _error} = result}, _module), do: result

  defp normalize_handle_message({:error, error}, _module), do: {:error, error}

  defp normalize_handle_message({:ok, result}, module) do
    {:error,
     Error.execution_error("Agent Exec handle_message returned an invalid result",
       details: %{module: module, result: inspect(result)}
     )}
  end

  defp normalize_cancel({:ok, :ok}, _module), do: :ok
  defp normalize_cancel({:ok, {:error, reason}}, _module), do: {:error, reason}
  defp normalize_cancel({:error, error}, _module), do: {:error, error}

  defp normalize_cancel({:ok, result}, module) do
    {:error,
     Error.execution_error("Agent Exec cancel returned an invalid result",
       details: %{module: module, result: inspect(result)}
     )}
  end

  defp invoke(module, callback, args) do
    {:ok, apply(module, callback, args)}
  rescue
    error -> {:error, callback_error(module, callback, :error, error)}
  catch
    kind, reason -> {:error, callback_error(module, callback, kind, reason)}
  end

  defp callback_error(module, callback, kind, reason) do
    Error.execution_error("Agent Exec callback failed",
      details: %{module: module, callback: callback, kind: kind, reason: reason}
    )
  end

  defp stop_handle(%{pid: pid}) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
    :ok
  end

  defp stop_handle(_handle), do: :ok

  defp finite_timeout(:infinity), do: @fallback_timeout
  defp finite_timeout(timeout), do: timeout

  defp start_timer(timeout, ref, token, callback) do
    :erlang.start_timer(timeout, self(), {:exec_adapter_timeout, ref, token, callback})
  end
end
