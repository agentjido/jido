defmodule Jido.AgentServer.Signal.Runtime do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.runtime",
    default_source: "/agent",
    schema: Zoi.object(%{})
end
