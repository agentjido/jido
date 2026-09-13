defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.MetadataList do
  use Jido.Agent, name: "invalid_metadata"

  agent do
    metadata case: "invalid"
  end
end
