defmodule Jido.Examples.Observability.SafeMetadata.Agent do
  @moduledoc "Keeps sensitive application data outside telemetry metadata."

  use Jido.Agent, name: "examples_observability_safe_metadata_agent"

  state do
    schema Jido.Joi.object(%{
             secret: Jido.Joi.string() |> Jido.Joi.default(""),
             value: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/observability/safe_metadata"

    route "examples.observability.safe_metadata.record", as: :record do
      action %{secret: secret, value: value},
        schema:
          Jido.Joi.object(%{
            secret: Jido.Joi.string() |> Jido.Joi.min(1),
            value: Jido.Joi.integer()
          }),
        context: context do
        {:ok, %{context.agent_state | secret: secret, value: value}}
      end
    end
  end
end
