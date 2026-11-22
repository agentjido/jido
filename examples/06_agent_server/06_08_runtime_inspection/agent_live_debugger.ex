defmodule Jido.Examples.AgentLiveDebugger do
  @moduledoc "A small observed Agent plus a read-only redacted inspection view."

  alias Jido.Joi

  use Jido.Agent,
    name: "examples_agent_live_debugger",
    description: "Provides public state for a safe debugger snapshot",
    plugins: [Jido.Plugin.Timer]

  state do
    schema Joi.object(%{
             status: Joi.string() |> Joi.default("idle"),
             secret_token: Joi.string() |> Joi.default("hidden"),
             result: Joi.string() |> Joi.default("")
           })
  end

  routes do
    signal_source "/examples/runtime/inspection"

    route "examples.runtime.inspection.record", as: :record_result do
      action %{result: result},
        schema: Joi.object(%{result: Joi.string()}),
        context: context do
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end
    end
  end

  alias Jido.AgentServer, as: Server

  def snapshot(server) do
    committed = Server.snapshot(server)
    agent = committed.agent
    status = Server.status(server)

    %{
      agent_id: agent.id,
      agent_module: agent.module,
      state: Map.take(agent.state, [:status, :result]),
      agent_revision: committed.agent_revision,
      work_state: status.work_state,
      active_turn_id: status.active_turn_id,
      effects: status.effects
    }
  end
end
