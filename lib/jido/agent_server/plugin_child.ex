defmodule Jido.AgentServer.PluginChild do
  @moduledoc false

  use GenServer

  alias Jido.AgentServer.Plugin.Callbacks
  alias Jido.AgentServer.TaskSupport

  @restart_poll_ms 10
  @restart_poll_attempts 500

  @doc false
  def start_link([owner, plugin_spec, child_spec, name, readiness_timeout]),
    do: start_link(owner, plugin_spec, child_spec, name, readiness_timeout)

  def start_link(owner, plugin_spec, child_spec, name, readiness_timeout)
      when is_pid(owner) and is_integer(readiness_timeout) and readiness_timeout > 0 do
    GenServer.start_link(
      __MODULE__,
      {owner, plugin_spec, child_spec, readiness_timeout},
      name: name
    )
  end

  @doc false
  def child_pid(server), do: GenServer.call(server, :child_pid)

  @impl true
  def init({owner, plugin_spec, child_spec, readiness_timeout}) do
    Process.flag(:trap_exit, true)
    Process.link(owner)

    with {:ok, supervisor} <-
           Supervisor.start_link([temporary_spec(child_spec)], strategy: :one_for_one),
         child_pid when is_pid(child_pid) <- supervised_child(supervisor, child_spec.id) do
      {:ok,
       %{
         owner: owner,
         supervisor: supervisor,
         child_pid: child_pid,
         child_ref: Process.monitor(child_pid),
         child_id: child_spec.id,
         plugin_spec: plugin_spec,
         readiness_timeout: readiness_timeout,
         readiness: nil,
         restart: nil
       }}
    else
      nil -> {:stop, :plugin_child_not_started}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:child_pid, _from, state) do
    {:reply, state.child_pid, state}
  end

  @impl true
  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    stop_child(state.child_pid, :shutdown)
    {:stop, {:shutdown, {:owner_down, reason}}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{child_ref: ref} = state) do
    send(state.owner, {:plugin_runtime_restarting, self(), state.child_id})
    state = stop_readiness(state)
    token = make_ref()
    send(state.owner, {:plugin_runtime_bootstrap, self(), state.child_id, token})

    {:noreply,
     %{
       state
       | child_pid: :restarting,
         child_ref: nil,
         restart: %{token: token, reason: reason, child_spec: nil}
     }}
  end

  def handle_info(
        {:plugin_runtime_bootstrap, token, {:ok, child_spec}},
        %{restart: %{token: token} = restart} = state
      ) do
    restart = %{restart | child_spec: child_spec}
    send(self(), {:start_plugin_runtime, token, @restart_poll_attempts})
    {:noreply, %{state | restart: restart}}
  end

  def handle_info(
        {:plugin_runtime_bootstrap, token, {:error, reason}},
        %{restart: %{token: token, reason: exit_reason}} = state
      ) do
    {:stop, {:plugin_runtime_bootstrap_failed, state.child_id, exit_reason, reason},
     %{state | restart: nil}}
  end

  def handle_info(
        {:start_plugin_runtime, token, attempts},
        %{restart: %{token: token, child_spec: child_spec, reason: reason}} = state
      )
      when not is_nil(child_spec) do
    case Supervisor.start_child(state.supervisor, temporary_spec(child_spec)) do
      {:ok, child_pid} when is_pid(child_pid) ->
        {:noreply, start_readiness(state, child_pid, reason)}

      {:ok, child_pid, _info} when is_pid(child_pid) ->
        {:noreply, start_readiness(state, child_pid, reason)}

      {:ok, :undefined} ->
        {:stop, {:plugin_runtime_restart_ignored, state.child_id, reason}, state}

      {:ok, :undefined, _info} ->
        {:stop, {:plugin_runtime_restart_ignored, state.child_id, reason}, state}

      {:error, {:already_started, child_pid}} when is_pid(child_pid) ->
        {:noreply, start_readiness(state, child_pid, reason)}

      {:error, error} when error in [:already_present, :running] and attempts > 0 ->
        Process.send_after(
          self(),
          {:start_plugin_runtime, token, attempts - 1},
          @restart_poll_ms
        )

        {:noreply, state}

      {:error, error} ->
        {:stop, {:plugin_runtime_restart_failed, state.child_id, reason, error}, state}
    end
  end

  def handle_info({ref, result}, %{readiness: %{task: %Task{ref: ref}} = readiness} = state) do
    TaskSupport.release_task_result(readiness)
    state = %{state | readiness: nil}

    case result do
      :ok ->
        child_pid = readiness.child_pid
        send(state.owner, {:plugin_runtime_ready, self(), state.child_id, child_pid})
        {:noreply, %{state | child_pid: child_pid}}

      {:error, reason} ->
        {:stop, {:plugin_runtime_readiness_failed, state.child_id, readiness.reason, reason},
         state}

      other ->
        {:stop,
         {:plugin_runtime_readiness_failed, state.child_id, readiness.reason,
          {:invalid_result, other}}, state}
    end
  end

  def handle_info(
        {:timeout, timer, {:plugin_readiness_timeout, ref}},
        %{readiness: %{task: %Task{ref: ref}, timer: timer} = readiness} = state
      ) do
    TaskSupport.shutdown_task(readiness.task)

    {:stop,
     {:plugin_runtime_readiness_timeout, state.child_id, readiness.reason,
      state.readiness_timeout}, %{state | readiness: nil}}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{readiness: %{task: %Task{ref: ref}} = readiness} = state
      ) do
    TaskSupport.cancel_task_timer(readiness.timer)

    {:stop, {:plugin_runtime_readiness_failed, state.child_id, readiness.reason, reason},
     %{state | readiness: nil}}
  end

  def handle_info({:EXIT, supervisor, reason}, %{supervisor: supervisor} = state) do
    {:stop, {:plugin_supervisor_exit, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = stop_readiness(state)

    stop_child(state.supervisor, :shutdown)
    :ok
  end

  defp supervised_child(supervisor, child_id) when is_pid(supervisor) do
    case Supervisor.which_children(supervisor) do
      [{^child_id, pid, _type, _modules}] when is_pid(pid) -> pid
      [{^child_id, :restarting, _type, _modules}] -> :restarting
      _children -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp start_readiness(state, child_pid, reason) do
    # Readiness can read Agent state. Keep child lookup responsive while
    # that work runs, or an Agent lookup can block the read it needs.
    task = Task.async(fn -> Callbacks.await_ready(state.plugin_spec, child_pid) end)

    timer =
      TaskSupport.start_task_timer(state.readiness_timeout, :plugin_readiness_timeout, task.ref)

    readiness = %{task: task, timer: timer, child_pid: child_pid, reason: reason}

    %{
      state
      | child_ref: Process.monitor(child_pid),
        readiness: readiness,
        restart: nil
    }
  end

  defp stop_readiness(%{readiness: nil} = state), do: state

  defp stop_readiness(%{readiness: readiness} = state) do
    TaskSupport.stop_task(readiness)
    %{state | readiness: nil}
  end

  # The Plugin declares permanent runtime intent. This wrapper owns the actual
  # restart so each new generation gets a fresh state-version bootstrap pair.
  defp temporary_spec(child_spec), do: Supervisor.child_spec(child_spec, restart: :temporary)

  defp stop_child(pid, reason) when is_pid(pid) do
    GenServer.stop(pid, reason, 5_000)
  catch
    :exit, _reason -> Process.exit(pid, reason)
  end

  defp stop_child(_child, _reason), do: :ok
end
