defmodule Jido.Examples.BusDelivery do
  @moduledoc """
  A durable Bus subscription delivers ordered Signals to an Agent. The Client
  acknowledges a record after its Turn commits. The Agent owns duplicate policy.
  The Bus and its cursor are local memory; this does not prove disk durability.
  Start the Bus in the same Jido instance as the Agent.
  """
  use Jido.Agent, name: "example_bus_delivery"

  agent do
    schema Zoi.object(%{
             seen: Zoi.list(Zoi.string()) |> Zoi.default([]),
             values: Zoi.list(Zoi.integer()) |> Zoi.default([])
           })

    plugin Jido.Plugin.Bus.Client,
      config: [
        bus: :example_commands,
        path: "examples.runtime.bus_delivery.**",
        durable: "example-consumer",
        start_from: :origin,
        retry_delay_ms: 10
      ]
  end

  routes do
    signal_source "/examples/runtime/bus_delivery"

    route "examples.runtime.bus_delivery.record" do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        state = context.agent_state
        signal_id = context.signal.id

        if signal_id in state.seen do
          # A retry of an already committed record must still succeed so that
          # the durable subscription can acknowledge it.
          {:ok, state}
        else
          {:ok, %{state | seen: state.seen ++ [signal_id], values: state.values ++ [value]}}
        end
      end

      define :record, args: [:value]
    end
  end
end
