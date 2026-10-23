defmodule JidoTest.AuthoringDocsAgent do
  @moduledoc false
  use Jido.Agent, name: "authoring_docs_agent"

  routes do
    signal_source "/authoring-docs"

    route "counter.increment", JidoTest.AgentFixtures.Add, as: :increment do
      state(from: output())
    end
  end
end
