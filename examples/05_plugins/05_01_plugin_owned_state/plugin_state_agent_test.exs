Code.require_file("count_turns.ex", __DIR__)
Code.require_file("plugin_state_agent.ex", __DIR__)

defmodule Jido.Examples.Basic.PluginStateAgentTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PluginStateAgent, as: Agent

  test "domain and Plugin state become visible in the same commit", %{jido: jido} do
    server = start_agent!(jido, Agent)

    {:ok, route_signal_1} = Agent.increment_signal(%{amount: 3})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.call(server, route_signal_1, [])

    committed = Server.snapshot(server).agent
    assert committed.state == %{count: 3, turns: 1}
    assert committed.state.turns == 1
    assert %Jido.AgentServer.Snapshot{agent: ^committed, agent_revision: 1} = Server.snapshot(server)
  end

  test "an Action cannot change Plugin-owned state", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Server.snapshot(server)

    {:ok, route_signal_2} = Agent.overwrite_plugin_state_signal(%{})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert inspect(error) =~ "Plugin-owned"
    assert Server.snapshot(server) == before
    assert Server.snapshot(server).agent.state.turns == 0

    {:ok, route_signal_3} = Agent.increment_signal(%{amount: 2})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.call(server, route_signal_3, [])

    recovered = Server.snapshot(server).agent
    assert recovered.state == %{count: 2, turns: 1}
    assert %Jido.AgentServer.Snapshot{agent: ^recovered, agent_revision: 1} = Server.snapshot(server)
  end

  test "invalid Plugin output rejects the domain candidate and preserves the prior commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent)

    {:ok, route_signal_4} = Agent.increment_signal(%{amount: 2})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} =
             Jido.AgentServer.call(server, route_signal_4, [])

    before = Server.snapshot(server)

    {:ok, route_signal_5} = Agent.increment_signal(%{amount: 5})

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert inspect(error) =~ "Plugin"
    assert Server.snapshot(server) == before
    assert Server.snapshot(server).agent.state.turns == 1
  end

  defp start_agent!(jido, agent, opts \\ []) do
    {:ok, server} =
      Jido.Test.AgentServer.ExampleRuntime.start_agent(
        jido,
        agent,
        Keyword.put_new(opts, :id, unique_id("plugin"))
      )

    assert :ok = Server.await_ready(server)
    server
  end
end
