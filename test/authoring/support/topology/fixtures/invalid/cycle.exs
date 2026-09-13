defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.Cycle do
  use Jido.Topology, name: "invalid_cycle"

  topology do
    agents do
      agent :a, JidoTest.Authoring.Topology.Fixtures.Worker, depends_on: [:b]
      agent :b, JidoTest.Authoring.Topology.Fixtures.Worker, depends_on: [:a]
    end
  end
end
