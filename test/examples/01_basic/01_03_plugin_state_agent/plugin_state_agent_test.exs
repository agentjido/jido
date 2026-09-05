defmodule JidoTest.Examples.Basic.PluginStateAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DirectiveAgent.Effects
  alias Jido.Examples.PluginStateAgent, as: Agent
  alias Jido.Examples.PluginStateAgent.CountTurns

  test "domain and Plugin state become visible in the same commit", %{jido: jido} do
    server = start_agent!(jido, Agent)

    assert {:ok, committed} = Server.call(server, change(3))
    assert committed.state == %{count: 3, turns: 1}
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}

    await_idle(server)
    assert [%{snapshot: %{agent: ^committed, state_version: 1}}] = Effects.records(server)
  end

  test "an Action cannot change Plugin-owned state or dispatch its otherwise valid effect", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    assert {:error, %Jido.Error.ExecutionError{} = error} = Server.call(server, change(3, true))
    assert_receive {:sdk_action, :change}
    assert error.message == "Agent executable changed Plugin-owned state"
    await_idle(server)
    assert Server.snapshot(server) == before
    assert {:ok, 0} = Server.plugin_state(server, CountTurns)
    assert Effects.records(server) == []

    assert {:ok, recovered} = Server.call(server, change(2))
    assert recovered.state == %{count: 2, turns: 1}
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
  end

  test "invalid Plugin output rejects the domain candidate and preserves the prior commit", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    assert {:ok, _} = Server.call(server, change(2))
    assert_receive {:sdk_action, :change}
    await_idle(server)
    before = Server.snapshot(server)
    records = Effects.records(server)
    assert length(records) == 1

    # The Action succeeds. The Plugin then proposes 2, outside its field
    # schema. No Directive is used to mutate Plugin or domain state.
    assert {:error, %Jido.Error.ExecutionError{} = error} = Server.call(server, change(5))
    assert_receive {:sdk_action, :change}
    assert error.message == "Agent Plugin state is invalid"
    await_idle(server)
    assert Server.snapshot(server) == before
    assert {:ok, 1} = Server.plugin_state(server, CountTurns)
    assert Effects.records(server) == records
  end

  defp change(amount, overwrite? \\ false) do
    Agent.increment_signal!(amount, input: %{overwrite?: overwrite?, observer: self()})
  end
end
