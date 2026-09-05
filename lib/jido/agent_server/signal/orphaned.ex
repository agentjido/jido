defmodule Jido.AgentServer.Signal.Orphaned do
  @moduledoc false

  use Jido.Signal,
    type: "jido.agent.orphaned",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        parent_id: Zoi.string(description: "Former parent Agent id"),
        parent_pid: Zoi.any(description: "Former parent PID"),
        tag: Zoi.any(description: "Former relationship tag"),
        meta: Zoi.map(description: "Former relationship metadata") |> Zoi.default(%{}),
        reason: Zoi.any(description: "Parent exit reason")
      })
end
