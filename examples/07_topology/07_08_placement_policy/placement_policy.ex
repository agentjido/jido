defmodule Jido.Examples.Topology.PlacementPolicy do
  @moduledoc "A control Agent that turns one policy Signal into an exact placement request."
  use Jido.Topology, name: "topology_placement_policy"

  alias Jido.Examples.Topology.PlacementPolicy.Move

  agent do
    schema Zoi.object(%{lifecycle_events: Zoi.integer() |> Zoi.default(0)})
    plugin Jido.Examples.Topology.PlacementPolicy.Plugin
  end

  routes do
    signal_source "/examples/topology/placement-policy"

    route "examples.topology.placement.request" do
      action input,
        schema:
          Zoi.object(%{
            topology_id: Zoi.string(),
            target: Zoi.any(),
            member: Zoi.any() |> Zoi.optional(),
            node: Zoi.atom()
          }),
        context: context do
        directive = %Move{
          topology_id: input.topology_id,
          target: input.target,
          member: Map.get(input, :member),
          node: input.node
        }

        {:ok, context.agent_state, [directive]}
      end

      define :place, args: [:topology_id, :target, :member, :node]
    end

    route "jido.topology.lifecycle.**" do
      action _input, context: context do
        {:ok,
         %{
           context.agent_state
           | lifecycle_events: context.agent_state.lifecycle_events + 1
         }}
      end
    end
  end

  topology do
    agents do
      group :workers, Jido.Examples.Topology.Cell, count: 2
    end
  end
end
