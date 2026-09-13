defmodule Jido.AgentServer.Signal.Error do
  @moduledoc "Reports a failed Agent Turn through the emit-signal error policy."

  use Jido.Signal,
    type: "jido.agent.error",
    default_source: "/agent",
    schema:
      Zoi.object(%{
        agent_id: Zoi.string(),
        turn_id: Zoi.string(),
        status: Zoi.enum([:failed, :cancelled, :timed_out, :indeterminate]),
        stage: Zoi.enum([:prepare, :execute, :finalize, :commit, :directive]),
        committed?: Zoi.boolean(),
        error: Zoi.map(description: "Transport error from Jido.Error.to_map/1")
      })
end
