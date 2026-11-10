defmodule Jido.Examples.TurnObservation do
  @moduledoc """
  A small Agent used to compare successful and failed semantic Turn events.

  The Agent emits no application telemetry. An external EventProbe collects
  public SDK events and filters them by Agent ID.
  """

  use Jido.Agent, name: "example_turn_observation"

  state do
    schema Jido.Joi.object(%{
             value: Jido.Joi.integer() |> Jido.Joi.default(0),
             secret: Jido.Joi.string() |> Jido.Joi.default("private-agent-state")
           })
  end

  routes do
    signal_source "/examples/runtime/observation"

    route "examples.runtime.observation.record", as: :record do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end
    end

    route "examples.runtime.observation.missing_child", as: :send_to_missing_child do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
        context: context do
        signal =
          Jido.Signal.new!("examples.runtime.observation.deliver", %{value: value},
            source: "/examples/runtime/observation"
          )

        directive = Jido.Agent.Directive.agent_send(:missing, signal)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end
    end
  end
end
