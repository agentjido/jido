defmodule Jido.Examples.Topology.LifecycleSignals do
  @moduledoc "A Topology with an optional Agent that receives lifecycle Signals."
  use Jido.Topology, name: "topology_lifecycle_signals"

  agent do
    schema Zoi.object(%{events: Zoi.list(Zoi.string()) |> Zoi.default([])})
  end

  routes do
    route "jido.topology.lifecycle.**" do
      action _input, context: context do
        {:ok,
         %{
           context.agent_state
           | events: context.agent_state.events ++ [context.signal.type]
         }}
      end
    end
  end

  topology do
    agents do
      agent :worker, Jido.Examples.Topology.Cell
    end
  end
end
