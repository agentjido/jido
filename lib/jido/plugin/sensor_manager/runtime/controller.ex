defmodule Jido.Plugin.SensorManager.Runtime.Controller do
  @moduledoc false

  use GenServer

  alias Jido.Plugin
  alias Jido.Plugin.Init, as: PluginInit
  alias Jido.Plugin.SensorManager.Init, as: SensorInit

  @default_retry_delay 1_000

  def start_link({%PluginInit{} = init, root}), do: GenServer.start_link(__MODULE__, {init, root})

  @impl true
  def init({%PluginInit{} = init, root}) do
    {:ok,
     %{
       desired: %{},
       init: init,
       last_reconciled_version: nil,
       retry_timer: nil,
       retry_token: nil,
       root: root,
       sensors: %{}
     }, {:continue, :restore}}
  end

  @impl true
  def handle_continue(:restore, state) do
    with {:ok, plugin_state} <- Plugin.state(state.init),
         {:ok, state} <- reconcile(state, plugin_state.desired) do
      {:noreply, state}
    else
      {:error, reason} -> {:stop, {:sensor_restore_failed, reason}, state}
      {:error, reason, state} -> {:stop, {:sensor_restore_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:await_ready, _from, state), do: {:reply, :ok, state}

  def handle_call(:sensors, _from, state) do
    sensors = Map.new(state.sensors, fn {tag, sensor} -> {tag, sensor.pid} end)
    {:reply, sensors, state}
  end

  def handle_call(
        {:reconcile, _desired, version},
        _from,
        %{last_reconciled_version: version} = state
      ) do
    {:reply, :ok, state}
  end

  def handle_call({:reconcile, desired, version}, _from, state) do
    case reconcile(state, desired) do
      {:ok, state} ->
        state = state |> cancel_retry() |> Map.put(:last_reconciled_version, version)
        {:reply, :ok, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, schedule_retry(state, version)}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.sensors, fn {_tag, sensor} -> sensor.ref == ref end) do
      {tag, _sensor} ->
        state = %{state | sensors: Map.delete(state.sensors, tag)}
        restart_sensor(state, tag)

      nil ->
        {:noreply, state}
    end
  end

  def handle_info({:retry_reconcile, token, version}, %{retry_token: token} = state) do
    state = %{state | retry_timer: nil, retry_token: nil}

    case reconcile(state, state.desired) do
      {:ok, state} -> {:noreply, %{state | last_reconciled_version: version}}
      {:error, _reason, state} -> {:noreply, schedule_retry(state, version)}
    end
  end

  def handle_info({:retry_reconcile, _token, _version}, state), do: {:noreply, state}

  defp reconcile(state, desired) when is_map(desired) do
    state = state |> stop_changed(desired) |> Map.put(:desired, desired)

    Enum.reduce_while(desired, {:ok, state}, &reconcile_sensor/2)
  end

  defp stop_changed(state, desired) do
    sensors =
      Enum.reduce(state.sensors, %{}, fn {tag, sensor}, kept ->
        keep_or_stop_sensor(state, desired, tag, sensor, kept)
      end)

    %{state | sensors: sensors}
  end

  defp same_spec?(left, right), do: left === right

  defp restart_sensor(state, tag) do
    case Map.fetch(state.desired, tag) do
      {:ok, spec} -> restart_sensor(state, tag, spec)
      :error -> {:noreply, state}
    end
  end

  defp restart_sensor(state, tag, spec) do
    case start_sensor(state, tag, spec) do
      {:ok, state} -> {:noreply, state}
      {:error, _reason, state} -> {:noreply, schedule_retry(state, state.last_reconciled_version)}
    end
  end

  defp reconcile_sensor({tag, spec}, {:ok, state}) do
    case Map.get(state.sensors, tag) do
      %{spec: current_spec, pid: pid} when is_pid(pid) ->
        continue_if_same_spec(state, tag, current_spec, spec)

      nil ->
        start_desired_sensor(state, tag, spec)
    end
  end

  defp continue_if_same_spec(state, tag, current_spec, desired_spec) do
    if same_spec?(current_spec, desired_spec) do
      {:cont, {:ok, state}}
    else
      {:halt, {:error, {:sensor_spec_mismatch, tag}, state}}
    end
  end

  defp start_desired_sensor(state, tag, spec) do
    case start_sensor(state, tag, spec) do
      {:ok, state} -> {:cont, {:ok, state}}
      {:error, reason, state} -> {:halt, {:error, {:sensor_start_failed, tag, reason}, state}}
    end
  end

  defp keep_or_stop_sensor(state, desired, tag, sensor, kept) do
    case Map.fetch(desired, tag) do
      {:ok, spec} -> keep_matching_sensor(state, tag, sensor, spec, kept)
      :error -> stop_and_discard_sensor(state, sensor, kept)
    end
  end

  defp keep_matching_sensor(state, tag, sensor, spec, kept) do
    if same_spec?(spec, sensor.spec) do
      Map.put(kept, tag, sensor)
    else
      stop_and_discard_sensor(state, sensor, kept)
    end
  end

  defp stop_and_discard_sensor(state, sensor, kept) do
    stop_sensor(state, sensor)
    kept
  end

  defp stop_sensor(state, sensor) do
    Process.demonitor(sensor.ref, [:flush])
    _ = DynamicSupervisor.terminate_child(sensor_supervisor(state), sensor.pid)
    :ok
  end

  defp start_sensor(state, tag, %{module: module, config: config} = spec) do
    init = %SensorInit{
      agent_server: state.init.agent_server,
      agent_id: state.init.agent_id,
      tag: tag,
      module: module,
      config: config,
      jido: state.init.jido,
      partition: state.init.partition
    }

    case sensor_child_spec(module, init, tag) do
      {:ok, child_spec} -> start_sensor_child(state, tag, spec, child_spec)
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp start_sensor_child(state, tag, spec, child_spec) do
    case DynamicSupervisor.start_child(sensor_supervisor(state), child_spec) do
      {:ok, pid} -> track_sensor(state, tag, spec, pid)
      {:ok, pid, _info} -> track_sensor(state, tag, spec, pid)
      {:error, reason} -> {:error, reason, state}
      :ignore -> {:error, :ignored, state}
    end
  end

  defp track_sensor(state, tag, spec, pid) do
    sensor = %{pid: pid, ref: Process.monitor(pid), spec: spec}
    {:ok, %{state | sensors: Map.put(state.sensors, tag, sensor)}}
  end

  defp sensor_child_spec(module, init, tag) do
    spec = Supervisor.child_spec({module, init}, id: {:sensor, tag})
    {:ok, Map.put(spec, :restart, :temporary)}
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp sensor_supervisor(state) do
    state.root
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {DynamicSupervisor, pid, :supervisor, _modules} when is_pid(pid) -> pid
      _child -> nil
    end)
  end

  defp schedule_retry(state, version) do
    state = cancel_retry(state)
    token = make_ref()
    delay = Keyword.get(state.init.options, :retry_delay_ms, @default_retry_delay)
    timer = Process.send_after(self(), {:retry_reconcile, token, version}, delay)
    %{state | retry_timer: timer, retry_token: token}
  end

  defp cancel_retry(%{retry_timer: nil} = state), do: state

  defp cancel_retry(state) do
    _ = Process.cancel_timer(state.retry_timer)
    %{state | retry_timer: nil, retry_token: nil}
  end
end
