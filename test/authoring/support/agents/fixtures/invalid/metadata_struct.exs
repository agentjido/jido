defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.MetadataStruct do
  use Jido.Agent, name: "invalid_metadata"

  agent do
    metadata ~D[2026-09-13]
  end
end
