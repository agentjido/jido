defmodule JidoTest.Examples.Basic.PluginStateAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PluginStateAgent, as: Agent
  alias Jido.Examples.PluginStateAgent.CountTurns

  test "domain and Plugin state become visible in the same commit", %{jido: jido} do
    server = start_agent!(jido, Agent)

    assert {:ok, committed} = Agent.increment(server, 3)
    assert committed.state == %{count: 3, turns: 1}
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "an Action cannot change Plugin-owned state", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    assert {:error, %Jido.Error.ExecutionError{} = error} =
             Agent.overwrite_plugin_state(server)

    assert error.message == "Agent executable changed Plugin-owned state"
    assert Server.snapshot(server) == before
    assert {:ok, 0} = Server.plugin_state(server, CountTurns)

    assert {:ok, recovered} = Agent.increment(server, 2)
    assert recovered.state == %{count: 2, turns: 1}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "invalid Plugin output rejects the domain candidate and preserves the prior commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    assert {:ok, _} = Agent.increment(server, 2)
    before = Server.snapshot(server)

    assert {:error, %Jido.Error.ExecutionError{} = error} = Agent.increment(server, 5)
    assert error.message == "Agent Plugin state is invalid"
    assert Server.snapshot(server) == before
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
  end
end
