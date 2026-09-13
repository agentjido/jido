defmodule JidoTest.Authoring.Topology.Fixtures.Invalid.MetadataRuntime do
  use Jido.Topology, name: "invalid_metadata"

  topology do
    metadata %{pid: self()}
  end
end
