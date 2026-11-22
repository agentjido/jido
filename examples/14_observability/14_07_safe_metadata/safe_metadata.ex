defmodule Jido.Examples.Observability.SafeMetadata.Agent do
  @moduledoc "Keeps sensitive application data outside telemetry metadata."

  alias Jido.Joi

  use Jido.Agent, name: "examples_observability_safe_metadata_agent"

  state do
    schema Joi.object(%{
             secret: Joi.string() |> Joi.default(""),
             value: Joi.integer() |> Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/observability/safe_metadata"

    route "examples.observability.safe_metadata.record", as: :record do
      action %{secret: secret, value: value},
        schema:
          Joi.object(%{
            secret: Joi.string() |> Joi.min(1),
            value: Joi.integer()
          }),
        context: context do
        {:ok, %{context.agent_state | secret: secret, value: value}}
      end
    end
  end
end
