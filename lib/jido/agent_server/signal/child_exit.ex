defmodule Jido.AgentServer.Signal.ChildExit do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.child.exit",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        tag: Zoi.any(description: "Tag assigned to the child when spawned"),
        pid: Zoi.any(description: "PID of the child process that exited"),
        reason: Zoi.any(description: "Exit reason from the child process")
      })
end
