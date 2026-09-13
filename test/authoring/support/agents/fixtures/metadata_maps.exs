defmodule JidoTest.Authoring.Agents.Fixtures.AtomMetadata do
  use Jido.Agent, name: "metadata_maps"

  agent do
    metadata %{case: "atom-key"}
  end
end

defmodule JidoTest.Authoring.Agents.Fixtures.StringMetadata do
  use Jido.Agent, name: "metadata_maps"

  agent do
    metadata %{"case" => "string-key"}
  end
end

defmodule JidoTest.Authoring.Agents.Fixtures.MixedMetadata do
  use Jido.Agent, name: "metadata_maps"

  agent do
    metadata %{"case" => "string-key", :case => "atom-key", :nested => %{"enabled" => false}}
  end
end
