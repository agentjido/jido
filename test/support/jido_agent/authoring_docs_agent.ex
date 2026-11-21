defmodule Jido.Test.Agent.AuthoringDocsAgent do
  @moduledoc false
  use Jido.Agent, name: "authoring_docs_agent"

  routes do
    signal_source "/authoring-docs"
    route "counter.increment", Jido.Test.AgentServer.Fixtures.Add, as: :increment
  end
end
