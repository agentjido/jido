defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MissingEndpoint do
  use Jido.Topology, name: "invalid_missing_endpoint"

  topology do
    agents do
      agent :worker, JidoTest.Authoring.Topology.Fixtures.Worker, depends_on: [:missing]
    end
  end
end
