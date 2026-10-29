defmodule Jido.Plugin.HeartbeatIntegrationTest do
  use JidoTest.Case, async: false

  alias Jido.AgentServer
  alias Jido.Plugin.Heartbeat

  defmodule RecordHeartbeat do
    use Jido.Action,
      name: "plugin_record_heartbeat"

    @impl Jido.Action
    def run(params, context) do
      {:ok, %{context.agent_state | heartbeats: context.agent_state.heartbeats ++ [params]}}
    end
  end

  defmodule Agent do
    use Jido.Agent,
      name: "plugin_heartbeat_integration_agent",
      plugins: [
        {Heartbeat,
         %{interval: 10, signal_type: "plugin.heartbeat", signal_data: %{source: :plugin}}}
      ]

    state do
      schema Zoi.object(%{heartbeats: Zoi.list(Zoi.any()) |> Zoi.default([])})
    end

    routes do
      route "plugin.heartbeat", RecordHeartbeat
    end
  end

  test "AgentServer starts the runtime and processes its Signals", %{jido: jido} do
    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(jido, Agent, id: unique_id("heartbeat"))

    eventually(fn ->
      case AgentServer.agent(server).state.heartbeats do
        [%{source: :plugin} | _rest] -> true
        _heartbeats -> false
      end
    end)

    assert %{pid: runtime} = JidoTest.AgentServerAssertions.plugin(server, Heartbeat)
    assert is_pid(runtime)
  end
end
