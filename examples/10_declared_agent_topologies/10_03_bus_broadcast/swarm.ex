defmodule Jido.Examples.Topology.Swarm do
  @moduledoc "A declared local Bus broadcasts each work output to three members."

  alias Jido.Joi

  use Jido.Agent, name: "topology_bus_swarm", plugins: [Jido.Plugin.Bus.DSL]

  state do
    schema Joi.object(%{sent: Joi.integer() |> Joi.default(0)})
  end

  routes do
    signal_source "/examples/topology/bus_swarm"

    route "examples.topology.cell.work", as: :work do
      action %{value: _value},
        schema: Joi.object(%{value: Joi.integer()}),
        context: context do
        {:ok, %{context.agent_state | sent: context.agent_state.sent + 1}, [Jido.Agent.Directive.emit(context.signal)]}
      end
    end
  end

  signal_bus do
    name :work
  end

  topology do
    agent :workers, Jido.Examples.Topology.Cell do
      count 3
      initial_state %{label: "worker"}
    end

    connections do
      connect "examples.topology.cell.work", from: :root, to: bus(:work)
      connect "examples.topology.cell.work", from: bus(:work), to: :workers, delivery: :broadcast
    end
  end
end
