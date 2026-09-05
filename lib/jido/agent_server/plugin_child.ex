defmodule Jido.AgentServer.PluginChild do
  @moduledoc false

  use GenServer

  alias Jido.Plugin

  @restart_poll_ms 10
  @restart_poll_attempts 500

  @doc false
  def start_link([owner, plugin_spec, child_spec]),
    do: start_link(owner, plugin_spec, child_spec)

  def start_link([owner, plugin_spec, child_spec, name]),
    do: start_link(owner, plugin_spec, child_spec, name)

  def start_link(owner, plugin_spec, child_spec) when is_pid(owner) do
    GenServer.start_link(__MODULE__, {owner, plugin_spec, child_spec})
  end

  def start_link(owner, plugin_spec, child_spec, nil) when is_pid(owner),
    do: start_link(owner, plugin_spec, child_spec)

  def start_link(owner, plugin_spec, child_spec, name) when is_pid(owner) do
    GenServer.start_link(__MODULE__, {owner, plugin_spec, child_spec}, name: name)
  end

  @doc false
  def child_pid(server), do: GenServer.call(server, :child_pid)

  @impl true
  def init({owner, plugin_spec, child_spec}) do
    Process.flag(:trap_exit, true)
    Process.link(owner)

    with {:ok, supervisor} <- Supervisor.start_link([child_spec], strategy: :one_for_one),
         child_pid when is_pid(child_pid) <- supervised_child(supervisor, child_spec.id) do
      {:ok,
       %{
         owner: owner,
         owner_ref: Process.monitor(owner),
         supervisor: supervisor,
         child_pid: child_pid,
         child_ref: Process.monitor(child_pid),
         child_id: child_spec.id,
         plugin_spec: plugin_spec
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
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{owner_ref: ref} = state) do
    stop_child(state.child_pid, :shutdown)
    {:stop, {:shutdown, {:owner_down, reason}}, state}
  end

  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    stop_child(state.child_pid, :shutdown)
    {:stop, {:shutdown, {:owner_down, reason}}, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{child_ref: ref} = state) do
    send(self(), {:await_child_restart, reason, @restart_poll_attempts})
    {:noreply, %{state | child_pid: :restarting, child_ref: nil}}
  end

  def handle_info({:await_child_restart, reason, attempts}, state) do
    case supervised_child(state.supervisor, state.child_id) do
      child_pid when is_pid(child_pid) ->
        case Plugin.await_ready(state.plugin_spec, child_pid) do
          :ok ->
            send(
              state.owner,
              {:plugin_runtime_ready, self(), state.child_id, child_pid}
            )

            {:noreply, %{state | child_pid: child_pid, child_ref: Process.monitor(child_pid)}}

          {:error, readiness_reason} ->
            {:stop, {:plugin_runtime_readiness_failed, state.child_id, reason, readiness_reason},
             state}
        end

      _child when attempts > 0 ->
        Process.send_after(
          self(),
          {:await_child_restart, reason, attempts - 1},
          @restart_poll_ms
        )

        {:noreply, state}

      _child ->
        {:stop, {:plugin_runtime_restart_timeout, state.child_id, reason}, state}
    end
  end

  def handle_info({:EXIT, supervisor, reason}, %{supervisor: supervisor} = state) do
    {:stop, {:plugin_supervisor_exit, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
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

  defp stop_child(pid, reason) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, reason, 5_000)
      catch
        :exit, _reason -> Process.exit(pid, reason)
      end
    end
  end

  defp stop_child(_child, _reason), do: :ok
end
