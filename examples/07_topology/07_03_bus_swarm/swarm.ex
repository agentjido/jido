defmodule Jido.Examples.Topology.Swarm do
  @moduledoc "A declared local Bus broadcasts each work output to three members."
  use Jido.Agent, name: "topology_bus_swarm", plugins: [Jido.Plugin.Bus.DSL]

  state do
    schema Zoi.object(%{
             sent: Zoi.integer() |> Zoi.default(0),
             worker_count: Zoi.integer() |> Zoi.min(1) |> Zoi.default(3)
           })
  end

  routes do
    signal_source "/examples/topology/bus_swarm"

    route "examples.topology.cell.work", as: :work do
      action %{value: _value},
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | sent: context.agent_state.sent + 1},
         [Jido.Agent.Directive.emit(context.signal)]}
      end
    end
  end

  signal_bus do
    name :work
  end

  topology do
    agent :workers, Jido.Examples.Topology.Cell do
      count state(:worker_count)
      initial_state %{label: "worker"}
    end

    connections do
      connect "examples.topology.cell.work", from: :root, to: bus(:work)
      connect "examples.topology.cell.work", from: bus(:work), to: :workers, delivery: :broadcast
    end
  end
end
