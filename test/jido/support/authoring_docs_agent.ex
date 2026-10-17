defmodule JidoTest.AuthoringDocsAgent do
  @moduledoc false
  use Jido.Agent, name: "authoring_docs_agent"

  agent do
  end

  routes do
    signal_source "/authoring-docs"
    route "counter.increment", JidoTest.AgentFixtures.Add, as: :increment
  end
end
