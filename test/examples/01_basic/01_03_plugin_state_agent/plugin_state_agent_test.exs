defmodule JidoTest.Examples.Basic.PluginStateAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.PluginStateAgent, as: Agent
  alias Jido.Examples.PluginStateAgent.CountTurns

  test "domain and Plugin state become visible in the same commit", %{jido: jido} do
    server = start_agent!(jido, Agent)

    {:ok, route_signal_1} = Agent.increment_signal(%{amount: 3})

    assert {:ok, committed} =
             Jido.AgentServer.call(server, route_signal_1, [])

    assert committed.state == %{count: 3, turns: 1}
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  test "an Action cannot change Plugin-owned state", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    {:ok, route_signal_2} = Agent.overwrite_plugin_state_signal(%{})

    assert {:error, %Jido.Error.ExecutionError{} = error} =
             Jido.AgentServer.call(server, route_signal_2, [])

    assert error.message == "Agent executable changed Plugin-owned state"
    assert Server.snapshot(server) == before
    assert {:ok, 0} = Server.plugin_state(server, CountTurns)

    {:ok, route_signal_3} = Agent.increment_signal(%{amount: 2})

    assert {:ok, recovered} =
             Jido.AgentServer.call(server, route_signal_3, [])

    assert recovered.state == %{count: 2, turns: 1}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "invalid Plugin output rejects the domain candidate and preserves the prior commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())

    {:ok, route_signal_4} = Agent.increment_signal(%{amount: 2})

    assert {:ok, _} =
             Jido.AgentServer.call(server, route_signal_4, [])

    before = Server.snapshot(server)

    {:ok, route_signal_5} = Agent.increment_signal(%{amount: 5})

    assert {:error, %Jido.Error.ExecutionError{} = error} =
             Jido.AgentServer.call(server, route_signal_5, [])

    assert error.message == "Plugin-owned Agent state field is invalid"
    assert Server.snapshot(server) == before
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
  end
end
