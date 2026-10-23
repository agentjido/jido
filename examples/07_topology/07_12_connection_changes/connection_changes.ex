defmodule Jido.Examples.Topology.ConnectionChanges do
  @moduledoc "Changes output connections while the named Agent processes stay live."
  use Jido.Agent, name: "topology_connection_changes"
  alias Jido.Agent.Directive, as: D
  @work "examples.topology.cell.work"

  routes do
    signal_source "/examples/topology/connection_changes"

    route "examples.topology.connections.redirect", as: :redirect do
      action %{value: value}, schema: Zoi.object(%{value: Zoi.integer()}), context: context do
        signal =
          Jido.Signal.new!("examples.topology.cell.work", %{value: value},
            source: "/examples/topology/connection_changes"
          )

        {:ok, context.agent_state,
         [
           D.connection_remove("examples.topology.cell.work", from: :root, to: :left),
           D.connection_add("examples.topology.cell.work", from: :root, to: :right),
           D.emit(signal)
         ]}
      end
    end

    route "examples.topology.connections.fanout", as: :fanout do
      action _input, context: context do
        {:ok, context.agent_state,
         [
           D.connection_add("examples.topology.cell.work", from: :root, to: :left),
           D.connection_update("examples.topology.cell.work",
             from: :root,
             to: :right,
             changes: %{delivery: :broadcast}
           ),
           D.connection_replace("examples.topology.cell.work",
             from: :root,
             to: :left,
             delivery: :broadcast
           )
         ]}
      end
    end

    route @work, as: :work do
      transform signal do
        {:ok, signal}
      end
    end
  end

  topology do
    agent :left, Jido.Examples.Topology.Cell do
      initial_state %{label: "left"}
    end

    agent :right, Jido.Examples.Topology.Cell do
      initial_state %{label: "right"}
    end

    connections do
      connect @work, from: :root, to: :left
    end
  end
end
