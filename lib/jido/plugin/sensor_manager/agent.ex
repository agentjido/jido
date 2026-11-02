defmodule Jido.Plugin.SensorManager.Agent do
  alias Jido.Joi
  @moduledoc false
  @behaviour Jido.Plugin

  alias Jido.Plugin.SensorManager.{Start, Stop}

  @sensor_schema Joi.object(%{module: Joi.module(), config: Joi.map() |> Joi.default(%{})})
  @state_schema Joi.object(%{desired: Joi.map(Joi.any(), @sensor_schema) |> Joi.default(%{})})
                |> Joi.default(%{})

  @impl true
  def state_spec(_opts), do: {:sensors, @state_schema}

  @impl true
  def directives(_opts), do: [Start, Stop]

  @impl true
  def reduce(reduction, _opts) do
    desired =
      Enum.reduce(reduction.directives, reduction.plugin_state.desired, &apply_directive/2)

    {:ok, %{reduction.plugin_state | desired: desired}}
  end

  defp apply_directive(%Start{tag: tag, sensor: sensor, config: config}, desired),
    do: Map.put(desired, tag, %{module: sensor, config: config})

  defp apply_directive(%Stop{tag: tag}, desired), do: Map.delete(desired, tag)
  defp apply_directive(_other, desired), do: desired
end
