defmodule Jido.Examples.Topology.Independent.Cell do
  @moduledoc "A small Agent for topology startup, ownership, and Bus examples."

  alias Jido.Joi

  use Jido.Agent,
    name: "topology_independent_cell",
    plugins: [{Jido.Plugin.Timer, %{retry_delay_ms: 25}}]

  state do
    schema Joi.object(%{
             label: Joi.string() |> Joi.default("cell"),
             received: Joi.integer() |> Joi.default(0),
             total: Joi.integer() |> Joi.default(0)
           })
  end

  routes do
    signal_source "/examples/topology/cell"

    route "examples.topology.cell.schedule", as: :schedule do
      action %{value: value},
        schema: Joi.object(%{value: Joi.integer()}),
        context: context do
        {:ok, signal} = Jido.Examples.Topology.Independent.Cell.work_signal(%{value: value})
        {:ok, context.agent_state, [Jido.Plugin.Timer.schedule(0, signal)]}
      end
    end

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
