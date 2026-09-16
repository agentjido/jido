defmodule Jido.AgentServer.PluginLifecycle do
  @moduledoc false

  alias Jido.AgentServer.Plugin.Callbacks
  alias Jido.Plugin.Init
  alias Jido.AgentServer.{ChildInfo, PluginChild, Shutdown, State}

  @doc false
  def start_all(%State{} = state) do
    case child_specs(state) do
      {:ok, child_specs} -> start_children(state, child_specs)
      {:error, reason} -> {:error, {:plugin_child_specs_failed, reason}, state}
    end
  end

  @doc false
  def replacement_child_spec(%State{} = state, plugin) when is_atom(plugin) do
    case Enum.find(state.plugin_specs, &(&1.module == plugin)) do
      nil ->
        {:error, {:plugin_spec_not_found, plugin}}

      plugin_spec ->
        with {:ok, [child_spec]} <- Callbacks.child_specs(init(state, plugin_spec), [plugin_spec]) do
          {:ok, child_spec}
        else
          {:ok, []} -> {:error, {:plugin_runtime_not_declared, plugin}}
          {:error, reason} -> {:error, {:plugin_child_spec_failed, plugin, reason}}
        end
    end
  end

  @doc false
  def await_all(%State{} = state) do
    Enum.reduce_while(state.plugin_specs, :ok, fn spec, :ok ->
      if spec.runtime? do
        with {:ok, runtime_ref} <- runtime_ref(state, spec.module),
             :ok <- Callbacks.await_ready(spec, runtime_ref) do
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
  def readiness_status(%State{} = state) do
    Enum.find_value(state.plugin_specs, :ready, &plugin_readiness(state, &1))
  end

  defp plugin_readiness(_state, %{runtime?: false}), do: false

  defp plugin_readiness(state, %{runtime?: true, module: plugin}) do
    case runtime_ref(state, plugin) do
      {:ok, pid} -> runtime_readiness(pid, plugin)
      {:error, {:plugin_runtime_unavailable, ^plugin, _state}} -> restarting(plugin)
      {:error, reason} -> {:error, reason}
    end
  end

  defp runtime_readiness(pid, plugin) when is_pid(pid) and node(pid) == node() do
    if Process.alive?(pid), do: false, else: restarting(plugin)
  end

  defp runtime_readiness(pid, plugin) when is_pid(pid) do
    try do
      if :erpc.call(node(pid), Process, :alive?, [pid], 1_000),
        do: false,
        else: restarting(plugin)
    catch
      _kind, _reason -> restarting(plugin)
    end
  end

  defp restarting(plugin), do: {:error, {:plugin_runtime_restarting, plugin}}

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

  defp child_specs(state) do
    state.plugin_specs
    |> Enum.reduce_while({:ok, []}, fn plugin_spec, {:ok, child_specs} ->
      case Callbacks.child_specs(init(state, plugin_spec), [plugin_spec]) do
        {:ok, specs} -> {:cont, {:ok, Enum.reverse(specs, child_specs)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, child_specs} -> {:ok, Enum.reverse(child_specs)}
      {:error, _reason} = error -> error
    end
  end

  defp init(%State{} = state, plugin_spec) do
    %Init{
      agent_server: self(),
      agent_id: state.agent.id,
      module: nil,
      plugin_state: owned_state(state.agent.state, plugin_spec),
      state_version: state.state_version,
      jido: state.jido,
      partition: state.partition,
      options: []
    }
  end

  defp owned_state(_agent_state, %{state_key: nil}), do: nil
  defp owned_state(agent_state, %{state_key: key}), do: Map.get(agent_state, key)

  defp start_child(state, %{id: plugin} = child_spec) do
    spec = Supervisor.child_spec(child_spec, [])
    plugin_spec = Enum.find(state.plugin_specs, &(&1.module == plugin))

    wrapper_spec =
      Supervisor.child_spec(
        {PluginChild,
         [self(), plugin_spec, spec, wrapper_name(state, plugin), state.readiness_timeout]},
        id: {:agent_plugin_child, state.agent.id, plugin},
        restart: :temporary
      )

    case start_wrapper(state, wrapper_spec) do
      {:ok, lifecycle_pid} ->
        track_plugin_child(state, plugin, spec, lifecycle_pid)

      {:error, reason} ->
        {:error, {:plugin_child_start_failed, plugin, reason}, state}
    end
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

    reason = Shutdown.normalize_reason(reason)

    try do
      GenServer.stop(pid, reason, 5_000)
    catch
      :exit, _reason -> Process.exit(pid, reason)
    end

    :ok
  end

  def handle_event(
        :info,
        {:plugin_runtime_restarting, lifecycle_pid, plugin},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    case State.child(data, key) do
      %ChildInfo{lifecycle_pid: ^lifecycle_pid} = child ->
        {:keep_state, State.add_child(data, key, %{child | pid: :restarting})}

      _child ->
        :keep_state_and_data
    end
  end

  def handle_event(
        :info,
        {:plugin_runtime_bootstrap, lifecycle_pid, plugin, token},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    result =
      case State.child(data, key) do
        %ChildInfo{lifecycle_pid: ^lifecycle_pid, pid: :restarting} ->
          replacement_child_spec(data, plugin)

        _child ->
          {:error, {:stale_plugin_runtime_bootstrap, plugin}}
      end

    send(lifecycle_pid, {:plugin_runtime_bootstrap, token, result})
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:plugin_runtime_ready, lifecycle_pid, plugin, runtime_pid},
        _phase,
        %State{} = data
      ) do
    key = {:plugin, plugin}

    case State.child(data, key) do
      %ChildInfo{lifecycle_pid: ^lifecycle_pid} = child ->
        {:keep_state, State.add_child(data, key, %{child | pid: runtime_pid})}

      _child ->
        :keep_state_and_data
    end
  end

  def plugin_state_value(_state, nil), do: nil
  def plugin_state_value(state, key), do: Map.get(state, key)

  def plugin_runtime_refs(%State{} = data, modules) do
    Enum.reduce_while(modules, {:ok, %{}}, fn module, {:ok, refs} ->
      spec = Enum.find(data.plugin_specs, &(&1.module == module))

      case plugin_runtime_ref(data, spec) do
        {:ok, runtime_ref} -> {:cont, {:ok, Map.put(refs, module, runtime_ref)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def plugin_runtime_ref(_data, %Jido.Plugin.Spec{runtime?: false}), do: {:ok, nil}

  def plugin_runtime_ref(data, %Jido.Plugin.Spec{module: module}) do
    runtime_ref(data, module)
  end
end
