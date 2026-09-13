defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MetadataStruct do
  use Jido.Topology, name: "invalid_metadata"

  topology do
    metadata ~D[2026-09-13]
  end
end
