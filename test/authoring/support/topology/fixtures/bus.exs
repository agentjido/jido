defmodule JidoTest.Authoring.Topology.Fixtures.Bus do
  use Jido.Topology, name: "authoring_bus"

  topology do
    agents do
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker
    end

    resources do
      bus :events
    end

    connections do
      subscribe :worker, to: :events, path: "authoring.work"
    end
  end
end
