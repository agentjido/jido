defmodule Jido.Examples.Observability.FailedTurn.Agent do
  @moduledoc "Validates one value before it can change committed state."

  use Jido.Agent, name: "examples_observability_failed_turn_agent"

  state do
    schema Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/observability/failed_turn"

    route "examples.observability.failed_turn.set", as: :set do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.min(0)}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end
    end
  end
end
