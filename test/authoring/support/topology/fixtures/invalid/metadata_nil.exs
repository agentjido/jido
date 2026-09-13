defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MetadataNil do
  use Jido.Topology, name: "invalid_metadata"

  topology do
    metadata nil
  end
end
