defmodule Jido.AgentServer.SensorLifecycle do
  @moduledoc false

  require Logger

  alias Jido.AgentServer
  alias Jido.AgentServer.{ChildInfo, State}
  alias Jido.Sensor.Runtime, as: SensorRuntime

  @stop_timeout 5_000

  @spec child_key(term()) :: {:sensor, term()}
  def child_key(tag), do: {:sensor, tag}

  @spec sensor_child?(ChildInfo.t() | term()) :: boolean()
  def sensor_child?(%ChildInfo{meta: %{kind: :sensor}}), do: true
  def sensor_child?(_child), do: false

  @spec start(State.t(), term(), module(), map() | keyword(), map(), keyword()) ::
          {:ok, State.t()}
  def start(%State{} = state, tag, sensor, config, meta, opts \\ []) do
    case validate_sensor_module(sensor) do
      :ok ->
        start_validated(state, tag, sensor, config, meta, opts)

      {:error, reason} ->
        Logger.warning(fn ->
          "AgentServer #{state.id} cannot start sensor #{inspect(tag)}: #{inspect(reason)}"
        end)

        {:ok, state}
    end
  end

  defp start_validated(state, tag, sensor, config, meta, opts) do
    replace? = Keyword.get(opts, :replace?, true)
    key = child_key(tag)

    case State.get_child(state, key) do
      %ChildInfo{} = child_info ->
        cond do
          sensor_child?(child_info) and replace? ->
            case stop_by_key(state, key, :replace) do
              {:stopped, state} -> start_new(state, tag, sensor, config, meta, opts)
              {_result, state} -> {:ok, state}
            end

          sensor_child?(child_info) ->
            {:ok, state}

          true ->
            Logger.warning(fn ->
              "AgentServer #{state.id} cannot start sensor #{inspect(tag)}: child key already in use"
            end)

            {:ok, state}
        end

      nil ->
        start_new(state, tag, sensor, config, meta, opts)
    end
  end

  @spec stop(State.t(), term(), term()) :: {:ok, State.t()}
  def stop(%State{} = state, tag, reason \\ :normal) do
    {_result, state} = stop_by_key(state, child_key(tag), reason)
    {:ok, state}
  end

  @spec stop_all(State.t(), term()) :: :ok
  def stop_all(%State{} = state, reason) do
    Enum.each(state.children, fn {_key, child_info} ->
      if sensor_child?(child_info) do
        case stop_child_info(child_info, reason) do
          :ok ->
            :ok

          {:error, stop_reason} ->
            Logger.warning(fn ->
              "AgentServer #{state.id} failed to stop sensor #{inspect(child_info.tag)} during shutdown: #{inspect(stop_reason)}"
            end)
        end
      end
    end)

    :ok
  end

  defp start_new(state, tag, sensor, config, meta, opts) do
    id = sensor_id(state, tag)
    origin = Keyword.get(opts, :origin, :directive)
    link? = Keyword.get(opts, :link?, false) == true

    runtime_opts = [
      sensor: sensor,
      config: config,
      context: sensor_context(state, tag, origin, Keyword.get(opts, :context, %{})),
      id: id,
      owner_pid: self()
    ]

    case start_sensor_runtime(runtime_opts, link?) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        key = child_key(tag)

        child_info =
          ChildInfo.new!(%{
            pid: pid,
            ref: ref,
            module: sensor,
            id: id,
            partition: state.partition,
            tag: key,
            meta: sensor_meta(tag, sensor, config, origin, meta, link?)
          })

        Logger.debug(fn ->
          "AgentServer #{state.id} started sensor #{inspect(tag)} with #{inspect(sensor)}"
        end)

        {:ok, State.add_child(state, key, child_info)}

      {:error, reason} ->
        Logger.warning(fn ->
          "AgentServer #{state.id} failed to start sensor #{inspect(tag)} with #{inspect(sensor)}: #{inspect(reason)}"
        end)

        {:ok, state}
    end
  end

  defp validate_sensor_module(sensor) when is_atom(sensor) and not is_nil(sensor) do
    case Code.ensure_loaded(sensor) do
      {:module, _module} -> :ok
      {:error, reason} -> {:error, {:sensor_not_loaded, sensor, reason}}
    end
  end

  defp validate_sensor_module(sensor), do: {:error, {:invalid_sensor_module, sensor}}

  defp start_sensor_runtime(runtime_opts, true), do: SensorRuntime.start_link(runtime_opts)
  defp start_sensor_runtime(runtime_opts, _linked?), do: SensorRuntime.start(runtime_opts)

  defp stop_by_key(state, key, reason) do
    case State.get_child(state, key) do
      nil ->
        Logger.debug(fn ->
          "AgentServer #{state.id} cannot stop sensor #{inspect(key)}: not found"
        end)

        {:missing, state}

      %ChildInfo{} = child_info ->
        if sensor_child?(child_info) do
          case stop_child_info(child_info, reason) do
            :ok ->
              {:stopped, State.remove_child(state, key)}

            {:error, stop_reason} ->
              Logger.warning(fn ->
                "AgentServer #{state.id} failed to stop sensor #{inspect(key)}: #{inspect(stop_reason)}"
              end)

              {:kept, state}
          end
        else
          Logger.warning(fn ->
            "AgentServer #{state.id} cannot stop sensor #{inspect(key)}: child key is not a sensor"
          end)

          {:kept, state}
        end
    end
  end

  defp stop_child_info(%ChildInfo{pid: pid, ref: ref} = child_info, reason) do
    cond do
      not is_pid(pid) or not Process.alive?(pid) ->
        demonitor(ref)
        :ok

      true ->
        unlinked? = maybe_unlink(child_info)

        case stop_sensor_pid(pid, normalize_stop_reason(reason)) do
          :ok ->
            demonitor(ref)
            :ok

          {:error, _reason} = error ->
            if Process.alive?(pid) do
              maybe_relink(child_info, unlinked?)
              error
            else
              demonitor(ref)
              :ok
            end
        end
    end
  end

  defp stop_sensor_pid(pid, reason) do
    GenServer.stop(pid, reason, @stop_timeout)
  catch
    :exit, {:noproc, _} ->
      :ok

    :exit, {:normal, _} ->
      :ok

    :exit, reason ->
      {:error, reason}
  end

  defp demonitor(ref) when is_reference(ref), do: Process.demonitor(ref, [:flush])
  defp demonitor(_ref), do: false

  defp maybe_unlink(%ChildInfo{pid: pid, meta: %{link?: true}}) when is_pid(pid) do
    Process.unlink(pid)
    true
  end

  defp maybe_unlink(_child_info), do: false

  defp maybe_relink(%ChildInfo{pid: pid}, true) when is_pid(pid) do
    Process.link(pid)
  catch
    :exit, :noproc -> :ok
  end

  defp maybe_relink(_child_info, _unlinked?), do: :ok

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:shutdown, _} = reason), do: reason
  defp normalize_stop_reason(:replace), do: {:shutdown, :replace}
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp sensor_context(state, tag, origin, extra_context) do
    base_context = %{
      agent_ref: AgentServer.via_tuple(state.id, state.registry, partition: state.partition),
      agent_id: state.id,
      agent_module: state.agent_module,
      jido_instance: state.jido,
      partition: state.partition
    }

    base_context
    |> Map.merge(normalize_map(extra_context))
    |> Map.put(:sensor_tag, tag)
    |> Map.put(:sensor_origin, origin)
  end

  defp sensor_meta(tag, sensor, config, origin, meta, link?) do
    Map.merge(normalize_map(meta), %{
      kind: :sensor,
      sensor: sensor,
      sensor_tag: tag,
      origin: origin,
      link?: link?,
      config_hash: :erlang.phash2(config)
    })
  end

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp sensor_id(state, tag) do
    "#{state.id}/sensor/#{inspect(tag)}"
  end
end
