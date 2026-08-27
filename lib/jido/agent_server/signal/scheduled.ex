defmodule Jido.AgentServer.Signal.Scheduled do
  @moduledoc false

  use Jido.Signal,
    type: "jido.scheduled",
    default_source: "/agent",
    schema: Zoi.object(%{message: Zoi.any(description: "The scheduled message payload")})
end
