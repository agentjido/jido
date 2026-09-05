defmodule Jido.Examples.Topology.Cell do
  @moduledoc "A small Agent for topology startup, ownership, and Bus examples."
  use Jido.Agent, name: "topology_cell"

  agent do
    schema Zoi.object(%{
             label: Zoi.string() |> Zoi.default("cell"),
             received: Zoi.integer() |> Zoi.default(0),
             total: Zoi.integer() |> Zoi.default(0)
           })
  end

  routes do
    signal_source "/examples/topology"

    route "topology.work" do
      action %{value: value},
        name: "topology_cell_work",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok,
         %{
           context.agent_state
           | received: context.agent_state.received + 1,
             total: context.agent_state.total + value
         }}
      end

      define :work, args: [:value]
    end

    route "jido.agent.**", Jido.Examples.KeepState
  end
end
