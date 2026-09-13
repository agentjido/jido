defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MetadataList do
  use Jido.Topology, name: "invalid_metadata"

  topology do
    metadata case: "invalid"
  end
end
