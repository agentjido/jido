defmodule Jido.Examples.AgentLiveDebugger do
  @moduledoc "A small observed Agent plus a read-only redacted inspection view."

  use Jido.Agent,
    name: "examples_agent_live_debugger",
    description: "Provides public state for a safe debugger snapshot",
    plugins: [Jido.Plugin.Scheduler]

  state do
    schema Jido.Joi.object(%{
             status: Jido.Joi.string() |> Jido.Joi.default("idle"),
             secret_token: Jido.Joi.string() |> Jido.Joi.default("hidden"),
             result: Jido.Joi.string() |> Jido.Joi.default("")
           })
  end

  routes do
    signal_source "/examples/runtime/inspection"

    route "examples.runtime.inspection.record", as: :record_result do
      action %{result: result},
        schema: Jido.Joi.object(%{result: Jido.Joi.string()}),
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
