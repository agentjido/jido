defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.BusIdentity do
  use Jido.Topology, name: "invalid_bus_identity"

  topology do
    resources do
      bus :events, config: [name: "foreign"]
    end
  end
end
