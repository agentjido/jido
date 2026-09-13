defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.DuplicateNames do
  use Jido.Topology, name: "invalid_duplicate_names"

  topology do
    agents do
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker
    end
  end
end
