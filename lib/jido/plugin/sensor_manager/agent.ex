defmodule Jido.Plugin.SensorManager.Agent do
  @moduledoc "Owns the desired sensor field in complete Agent state."
  use Jido.Agent.Plugin

  alias Jido.Plugin.SensorManager.{Start, Stop}

  @sensor_schema Zoi.object(%{module: Zoi.module(), config: Zoi.map() |> Zoi.default(%{})})
  @state_schema Zoi.object(%{desired: Zoi.map(Zoi.any(), @sensor_schema) |> Zoi.default(%{})})
                |> Zoi.default(%{desired: %{}})

  @impl true
  def state_spec(_opts), do: {:sensors, @state_schema}

  @impl true
  def directives(_opts), do: [Start, Stop]

  @impl true
  def reduce(reduction, _opts) do
    desired =
      Enum.reduce(reduction.directives, reduction.plugin_state.desired, fn
        %Start{tag: tag, sensor: sensor, config: config}, desired ->
          Map.put(desired, tag, %{module: sensor, config: config})

        %Stop{tag: tag}, desired ->
          Map.delete(desired, tag)

        _other, desired ->
          desired
      end)

    {:ok, %{reduction.plugin_state | desired: desired}}
  end
end
