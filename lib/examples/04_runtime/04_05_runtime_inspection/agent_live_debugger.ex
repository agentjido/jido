defmodule Jido.Examples.AgentLiveDebugger do
  @moduledoc "A small observed Agent plus a read-only redacted snapshot function."

  use Jido.Agent,
    name: "examples_agent_live_debugger",
    description: "Provides public state for a safe debugger snapshot"

  agent do
    schema Zoi.object(%{
             status: Zoi.string() |> Zoi.default("idle"),
             secret_token: Zoi.string() |> Zoi.default("hidden"),
             result: Zoi.string() |> Zoi.default("")
           })
  end

  routes do
    signal_source "/examples/agent_live_debugger"

    route "examples.debug.work" do
      action %{result: result}, name: "examples_agent_live_debugger_work", context: context do
        if observer = context[:on_work], do: observer.(%{result: result})
        {:ok, %{context.agent_state | status: "complete", result: result}}
      end

      define :record_result
    end
  end

  alias Jido.AgentServer, as: Server

  def snapshot(server) do
    %{agent: agent, state_version: version} = Server.snapshot(server)
    status = Server.status(server)

    %{
      agent_id: agent.id,
      agent_module: agent.module,
      state: Map.drop(agent.state, [:secret_token]),
      state_version: version,
      runtime_status: status.phase
    }
  end
end
