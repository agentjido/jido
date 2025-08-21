defmodule Jido.Agent.Server.Sensors do
  @moduledoc false

  @doc """
  Builds sensor configuration by injecting the agent pid into sensor targets and preparing child specs.

  ## Parameters
  - state: Current server state
  - opts: Configuration options containing sensor specs
  - agent_pid: PID of the agent process that will receive sensor signals

  ## Returns
  - `{:ok, state, opts}` - Sensors configured successfully
  - `{:error, reason}` - Failed to configure sensors
  """
  def build(state, opts, agent_pid) when is_pid(agent_pid) do
    case get_sensor_specs(opts) do
      {:ok, sensors} ->
        # Prepare sensors with agent_pid as target
        sensors_with_target = prepare_sensor_specs(sensors, agent_pid)
        # Update opts with prepared sensors in child_specs
        updated_opts =
          opts
          |> Keyword.update(:child_specs, sensors_with_target, fn existing_specs ->
            (List.wrap(existing_specs) ++ sensors_with_target)
            |> Enum.uniq()
          end)

        {:ok, state, updated_opts}

      {:error, _} = error ->
        error
    end
  end

  def build(_state, _opts, _agent_pid) do
    {:error, :invalid_agent_pid}
  end

  # Private Functions

  defp get_sensor_specs(opts) do
    case Keyword.get(opts, :sensors) do
      nil ->
        {:ok, []}

      sensors when is_list(sensors) ->
        {:ok, sensors}

      _invalid ->
        {:error, :invalid_sensors_config}
    end
  end

  defp prepare_sensor_specs(sensors, agent_pid) do
    prepared =
      Enum.map(sensors, fn
        {module, sensor_opts} when is_list(sensor_opts) ->
          {module, add_target_to_opts(sensor_opts, agent_pid)}

        other ->
          other
      end)

    prepared
  end

  defp add_target_to_opts(sensor_opts, agent_pid) when is_list(sensor_opts) do
    case Keyword.get(sensor_opts, :target) do
      nil ->
        Keyword.put(sensor_opts, :target, agent_pid)

      existing_target when is_list(existing_target) ->
        Keyword.put(sensor_opts, :target, existing_target ++ [agent_pid])

      existing_target ->
        Keyword.put(sensor_opts, :target, [existing_target, agent_pid])
    end
  end
end
