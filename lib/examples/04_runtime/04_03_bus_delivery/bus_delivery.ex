defmodule Jido.Examples.BusDelivery.Record do
  @moduledoc false
  use Jido.Action,
    name: "example_bus_record",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(input, context) do
    if observer = context[:on_delivery], do: observer.(input)
    state = context.agent_state
    id = context.signal.id

    if id in state.seen do
      # Durable delivery must acknowledge a retry that was already committed.
      {:ok, state}
    else
      {:ok, %{state | seen: state.seen ++ [id], values: state.values ++ [input.value]}}
    end
  end
end

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
        path: "examples.bus.**",
        durable: "example-consumer",
        start_from: :origin,
        retry_delay_ms: 10
      ]
  end

  routes do
    signal_source "/examples/bus"

    route "examples.bus.record", Jido.Examples.BusDelivery.Record do
      define :record, args: [:value]
    end
  end
end
