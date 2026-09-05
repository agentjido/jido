defmodule Jido.AgentServer.Signal.ChildExit do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.child.exit",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        tag: Zoi.any(description: "Tracked child tag"),
        child_id: Zoi.string(description: "Child Agent id"),
        pid: Zoi.any(description: "Child Agent Server PID"),
        reason: Zoi.any(description: "Process exit reason")
      })
end
