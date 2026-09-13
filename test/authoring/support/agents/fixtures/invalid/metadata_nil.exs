defmodule JidoTest.Authoring.Agents.Fixtures.Invalid.MetadataNil do
  use Jido.Agent, name: "invalid_metadata"

  agent do
    metadata nil
  end
end
