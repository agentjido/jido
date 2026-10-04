defmodule Jido.Examples.Research.ChildTopologyRuntime.Child do
  @moduledoc "A combined director and Topology with two members and a private Bus."
  use Jido.Topology, name: "child_runtime_child"

  agent do
    schema Zoi.object(%{events: Zoi.list(Zoi.map()) |> Zoi.default([])})
  end

  routes do
    signal_source "/examples/research/child_runtime/child/director"

    route "jido.topology.lifecycle.**",
          Jido.Examples.Research.ChildTopologyRuntime.Observe
  end

  topology do
    agents do
      agent :alice, Jido.Examples.Research.ChildTopologyRuntime.Worker,
        initial_state: %{label: "Alice"}

      agent :bob, Jido.Examples.Research.ChildTopologyRuntime.Worker,
        initial_state: %{label: "Bob"}
    end

    resources do
      bus :signals
    end

    connections do
      subscribe :alice, to: :signals, path: "examples.research.child_runtime.record"
      subscribe :bob, to: :signals, path: "examples.research.child_runtime.record"
    end

    exports do
      agent :alice, from: :alice
      agent :bob, from: :bob
      bus :signals, from: :signals
    end
  end
end
