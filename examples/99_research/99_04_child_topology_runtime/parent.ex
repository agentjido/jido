defmodule Jido.Examples.Research.ChildTopologyRuntime.Parent do
  @moduledoc "The parent director and its own Bus. Child declarations are data proposals."
  use Jido.Topology, name: "child_runtime_parent"

  agent do
    schema Zoi.object(%{events: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/research/child_runtime/parent/director"

    route "jido.topology.lifecycle.**",
          Jido.Examples.Research.ChildTopologyRuntime.Observe
  end

  topology do
    resources do
      bus :signals
    end
  end
end
