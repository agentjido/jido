defmodule Jido.Examples.Topology.Cell do
  @moduledoc "A small Agent for topology startup, ownership, and Bus examples."
  use Jido.Agent, name: "topology_cell"

  state do
    schema Jido.Joi.object(%{
             label: Jido.Joi.string() |> Jido.Joi.default("cell"),
             received: Jido.Joi.integer() |> Jido.Joi.default(0),
             total: Jido.Joi.integer() |> Jido.Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/topology/cell"

    route "examples.topology.cell.work", as: :work do
      action %{value: value},
        schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
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
