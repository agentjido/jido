defmodule Jido.Examples.TurnObservation do
  @moduledoc """
  A small Agent used to compare successful and failed semantic Turn events.

  The Agent emits no application telemetry. An external EventProbe collects
  public SDK events and filters them by Agent ID.
  """

  use Jido.Agent, name: "example_turn_observation"

  agent do
    schema Zoi.object(%{
             value: Zoi.integer() |> Zoi.default(0),
             secret: Zoi.string() |> Zoi.default("private-agent-state")
           })
  end

  routes do
    signal_source "/examples/runtime/observation"

    route "examples.runtime.observation.record" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end

      define :record, args: [:value]
    end

    route "examples.runtime.observation.missing_child" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        signal =
          Jido.Signal.new!("examples.runtime.observation.deliver", %{value: value},
            source: "/examples/runtime/observation"
          )

        directive = Jido.Agent.Directive.emit_to_child(:missing, signal)
        {:ok, %{context.agent_state | value: value}, [directive]}
      end

      define :send_to_missing_child, args: [:value]
    end
  end
end
