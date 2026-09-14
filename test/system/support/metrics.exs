defmodule JidoTest.System.Metrics do
  @moduledoc false
  import ExUnit.Callbacks

  # A small host-side reporter for the two metric types used by this suite.
  # Event names and tags come from the public metric definitions.
  def start!(namespace, metrics) do
    recorder = start_supervised!({Agent, fn -> %{} end}, id: __MODULE__)
    id = {__MODULE__, make_ref()}
    events = metrics |> Enum.map(& &1.event_name) |> Enum.uniq()
    :ok = :telemetry.attach_many(id, events, &__MODULE__.record/4, {namespace, recorder, metrics})
    on_exit(fn -> :telemetry.detach(id) end)
    recorder
  end

  def record(event, measurements, metadata, {namespace, recorder, metrics}) do
    if metadata[:agent_namespace] == namespace do
      for metric <- metrics, metric.event_name == event do
        key = {metric.name, Map.take(metadata, metric.tags)}

        case metric do
          %Telemetry.Metrics.Counter{} ->
            Agent.update(recorder, &Map.update(&1, key, 1, fn n -> n + 1 end))

          %Telemetry.Metrics.LastValue{measurement: measurement} ->
            if value = measurements[measurement],
              do: Agent.update(recorder, &Map.put(&1, key, value))
        end
      end
    end
  end

  def values(recorder), do: Agent.get(recorder, & &1)
end
