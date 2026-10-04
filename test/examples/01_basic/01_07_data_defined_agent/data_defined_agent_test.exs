defmodule JidoTest.Examples.Basic.DataDefinedAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.Examples.DataDefinedAgent, as: Example

  test "a trusted static definition has equal direct and live execution", %{jido: jido} do
    {document, registry} = Example.encode()
    assert {:ok, definition} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert definition == Example.definition()

    [plugin_document] = document["plugins"]

    assert {:ok, {Example.CountTurns, []}} =
             Jido.Plugin.Codec.decode(plugin_document, registry)

    direct = Agent.instantiate!(definition, id: unique_id("data-defined-direct"))
    assert {:ok, direct} = Agent.set(direct, count: 4)
    live = Agent.instantiate!(definition, id: unique_id("data-defined-live"), state: direct.state)
    {:ok, server} = Jido.start_agent(jido, live)
    signal = Example.signal!(3)

    assert {:ok, direct_result, []} = Agent.cmd(direct, signal)
    assert {:ok, live_result} = Jido.AgentServer.call(server, signal)
    assert direct_result.state == %{count: 7, turns: 1}
    assert live_result.state == direct_result.state
  end

  test "an unknown Registry target cannot enter the definition" do
    {document, registry} = Example.encode()
    [route] = document["routes"]
    untrusted = %{document | "routes" => [%{route | "target" => "actions/untrusted"}]}

    assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(untrusted, registry)
  end
end
