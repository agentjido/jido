defmodule Jido.AgentServer.PluginLifecycle do
  @moduledoc false

  alias Jido.Plugin
  alias Jido.Plugin.Init
  alias Jido.AgentServer.{ChildInfo, PluginChild, State}

  @doc false
  def start_all(%State{} = state) do
    init = %Init{
      agent_server: self(),
      agent_id: state.agent.id,
      module: nil,
      jido: state.jido,
      partition: state.partition,
      options: []
    }

    case Plugin.child_specs(init, state.agent.plugins) do
      {:ok, child_specs} -> start_children(state, child_specs)
      {:error, reason} -> {:error, {:plugin_child_specs_failed, reason}, state}
    end
  end

  @doc false
  def await_all(%State{} = state) do
    Enum.reduce_while(state.plugin_specs, :ok, fn spec, :ok ->
      if spec.runtime? do
        with {:ok, runtime_ref} <- runtime_ref(state, spec.module),
             :ok <- Plugin.await_ready(spec, runtime_ref) do
          {:cont, :ok}
        else
          {:error, reason} -> {:halt, {:error, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  @doc false
  def runtime_ref(%State{} = state, plugin) when is_atom(plugin) do
    case State.child(state, {:plugin, plugin}) do
      %ChildInfo{lifecycle_pid: lifecycle_pid} when is_pid(lifecycle_pid) ->
        case PluginChild.child_pid(lifecycle_pid) do
          pid when is_pid(pid) -> {:ok, pid}
          value -> {:error, {:plugin_runtime_unavailable, plugin, value}}
        end

      %ChildInfo{pid: pid} when is_pid(pid) ->
        {:ok, pid}

      nil ->
        {:error, {:plugin_runtime_not_found, plugin}}
    end
  catch
    :exit, reason -> {:error, {:plugin_runtime_unavailable, plugin, reason}}
  end

  @doc false
  def stop_all(%State{} = state, reason) do
    Enum.each(state.children, fn
      {_key, %ChildInfo{kind: :plugin} = child} -> stop_child(child, reason)
      _entry -> :ok
    end)

    :ok
  end

  defp start_children(state, child_specs) do
    Enum.reduce_while(child_specs, {:ok, state}, fn child_spec, {:ok, acc} ->
      case start_child(acc, child_spec) do
        {:ok, next_state} -> {:cont, {:ok, next_state}}
        error -> {:halt, error}
      end
    end)
  end

  defp start_child(state, %{id: plugin} = child_spec) when is_atom(plugin) do
    spec = Supervisor.child_spec(child_spec, [])
    plugin_spec = Enum.find(state.plugin_specs, &(&1.module == plugin))

    if plugin_spec do
      wrapper_spec =
        Supervisor.child_spec(
          {PluginChild, [self(), plugin_spec, spec, wrapper_name(state, plugin)]},
          id: {:agent_plugin_child, state.agent.id, plugin},
          restart: :temporary
        )

      case start_wrapper(state, wrapper_spec) do
        {:ok, lifecycle_pid} ->
          track_plugin_child(state, plugin, spec, lifecycle_pid)

        {:ok, lifecycle_pid, _info} ->
          track_plugin_child(state, plugin, spec, lifecycle_pid)

        :ignore ->
          {:ok, state}

        {:error, reason} ->
          {:error, {:plugin_child_start_failed, plugin, reason}, state}
      end
    else
      {:error, {:plugin_spec_not_found, plugin}, state}
    end
  end

  defp start_child(state, child_spec) do
    {:error, {:invalid_plugin_child_spec_id, child_spec}, state}
  end

  defp start_wrapper(%State{jido: jido}, wrapper_spec)
       when is_atom(jido) and not is_nil(jido) do
    supervisor = Jido.agent_supervisor_name(jido)

    case DynamicSupervisor.start_child(supervisor, wrapper_spec) do
      {:error, {:already_started, pid}} ->
        restart_after_previous_stops(supervisor, wrapper_spec, pid)

      result ->
        result
    end
  end

  defp start_wrapper(%State{}, %{start: {module, function, args}}) do
    case apply(module, function, args) do
      {:ok, pid} = result ->
        Process.unlink(pid)
        result

      result ->
        result
    end
  end

  defp track_plugin_child(state, plugin, spec, lifecycle_pid) do
    with pid when is_pid(pid) <- PluginChild.child_pid(lifecycle_pid) do
      key = {:plugin, plugin}

      child =
        ChildInfo.new!(
          pid: pid,
          lifecycle_pid: lifecycle_pid,
          ref: Process.monitor(lifecycle_pid),
          module: plugin,
          id: "#{state.agent.id}/plugin/#{inspect(plugin)}",
          partition: state.partition,
          tag: key,
          kind: :plugin,
          meta: %{child_spec_id: spec.id}
        )

      {:ok, State.add_child(state, key, child)}
    else
      value -> {:error, {:plugin_child_pid_invalid, plugin, value}, state}
    end
  end

  defp wrapper_name(%State{registry: registry} = state, plugin)
       when is_atom(registry) and not is_nil(registry) do
    key = {:agent_plugin, Jido.partition_key(state.agent.id, state.partition), plugin}
    {:via, Registry, {registry, key}}
  end

  defp wrapper_name(%State{}, _plugin), do: nil

  defp restart_after_previous_stops(supervisor, wrapper_spec, pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} ->
        DynamicSupervisor.start_child(supervisor, wrapper_spec)
    after
      5_000 ->
        Process.demonitor(ref, [:flush])
        {:error, {:previous_plugin_runtime_still_running, pid}}
    end
  end

  defp stop_child(%ChildInfo{} = child, reason) do
    Process.demonitor(child.ref, [:flush])

    pid = child.lifecycle_pid || child.pid

    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, normalize_stop_reason(reason), 5_000)
      catch
        :exit, _reason -> Process.exit(pid, normalize_stop_reason(reason))
      end
    end

    :ok
  end

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _reason} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}
end
