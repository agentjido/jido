defmodule Jido.Examples.Observability.OpenTelemetry.Agent do
  @moduledoc "Produces one Jido Turn that the host OpenTelemetry tracer observes."

  use Jido.Agent, name: "examples_observability_open_telemetry_agent"

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/observability/open_telemetry"

    route "examples.observability.open_telemetry.record", as: :record do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end
    end
  end
end
