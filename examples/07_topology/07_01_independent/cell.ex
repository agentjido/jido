defmodule Jido.Examples.Topology.Independent.Cell do
  @moduledoc "A small Agent for topology startup, ownership, and Bus examples."
  use Jido.Agent, name: "topology_independent_cell"

  state do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("cell"),
             received: Zoi.integer() |> Zoi.default(0),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  plugins do
    plugin Jido.Plugin.Scheduler, config: %{retry_delay_ms: 25}
  end

  routes do
    signal_source "/examples/topology/cell"

    route "examples.topology.cell.schedule", as: :schedule do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, signal} = Jido.Examples.Topology.Independent.Cell.work_signal(%{value: value})
        {:ok, context.agent_state, [Jido.Plugin.Scheduler.schedule(0, signal)]}
      end
    end

    route "examples.topology.cell.work", as: :work do
      action %{value: value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok,
         %{
           context.agent_state
           | received: context.agent_state.received + 1,
             total: context.agent_state.total + value
         }}
      end
    end
  end
end
