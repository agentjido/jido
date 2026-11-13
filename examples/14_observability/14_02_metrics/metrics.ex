defmodule Jido.Examples.Observability.Metrics.Agent do
  @moduledoc "Produces one successful Turn for a local metrics reporter."

  use Jido.Agent, name: "examples_observability_metrics_agent"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/observability/metrics"

    route "examples.observability.metrics.increment", as: :increment do
      action _input, context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Observability.Metrics.Catalog do
  @moduledoc "Projects the public Jido metric definitions for a host reporter."

  @doc "Returns metric names, event names, tags, and units as portable data."
  @spec entries() :: [map()]
  def entries do
    Enum.map(Jido.Telemetry.metrics(), fn metric ->
      %{
        event_name: metric.event_name,
        name: metric.name,
        tags: metric.tags,
        unit: metric.unit
      }
    end)
  end
end

defmodule Jido.Examples.Observability.Metrics.Reporter do
  @moduledoc "Forwards selected metric events to one local owner."

  @doc false
  def capture(event, measurements, metadata, owner) do
    send(owner, {:metric_event, event, measurements, metadata})
  end
end
