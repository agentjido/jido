defmodule Jido.Examples.Topology.Cell do
  @moduledoc "A small Agent for topology startup, ownership, and Bus examples."

  alias Jido.Joi

  use Jido.Agent, name: "topology_cell"

  state do
    schema Joi.object(%{
             label: Joi.string() |> Joi.default("cell"),
             received: Joi.integer() |> Joi.default(0),
             total: Joi.integer() |> Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/topology/cell"

    route "examples.topology.cell.work", as: :work do
      action %{value: value},
        schema: Joi.object(%{value: Joi.integer()}),
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
