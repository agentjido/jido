defmodule JidoTest.Authoring.Topology.Fixtures.AtomMetadata do
  use Jido.Topology, name: "metadata_maps"

  topology do
    metadata %{case: "atom"}
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.StringMetadata do
  use Jido.Topology, name: "metadata_maps"

  topology do
    metadata %{"case" => "string"}
  end
end

defmodule JidoTest.Authoring.Topology.Fixtures.MixedMetadata do
  use Jido.Topology, name: "metadata_maps"

  topology do
    metadata %{"case" => "string", :case => "atom"}
  end
end
