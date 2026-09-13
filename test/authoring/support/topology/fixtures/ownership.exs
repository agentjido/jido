defmodule JidoTest.Authoring.Topology.Fixtures.Ownership do
  use Jido.Topology, name: "authoring_ownership"

  topology do
    agents do
      agent :parent, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :child, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :observer, JidoTest.Authoring.Topology.Fixtures.Worker, depends_on: [:child]
    end

    relationships do
      owns :parent, :child, on_parent_exit: :continue
    end
  end
end
