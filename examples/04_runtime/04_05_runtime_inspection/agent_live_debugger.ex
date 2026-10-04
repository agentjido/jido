defmodule Jido.Examples.AgentLiveDebugger do
  @moduledoc "A small observed Agent plus a read-only redacted inspection view."

  use Jido.Agent,
    name: "examples_agent_live_debugger",
    description: "Provides public state for a safe debugger snapshot"

  agent do
    schema Zoi.object(%{
             status: Zoi.string() |> Zoi.default("idle"),
             secret_token: Zoi.string() |> Zoi.default("hidden"),
             result: Zoi.string() |> Zoi.default("")
           })

    plugin Jido.Plugin.Scheduler
  end

  routes do
    signal_source "/examples/runtime/inspection"

    route "examples.runtime.inspection.record", as: :record_result do
      action %{result: result},
        schema: Zoi.object(%{result: Zoi.string()}),
        context: context do
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end
    end
  end

  alias Jido.AgentServer, as: Server

  def snapshot(server) do
    agent = Server.agent(server)
    %{state_version: version} = Server.snapshot(server)
    status = Server.status(server)
    {:ok, scheduler} = Server.plugin_state(server, Jido.Plugin.Scheduler)

    %{
      agent_id: agent.id,
      agent_module: agent.module,
      state: Map.take(agent.state, [:status, :result]),
      state_version: version,
      runtime_status: status.phase,
      active: status.active,
      scheduler: scheduler,
      children: Server.children(server)
    }
  end
end
