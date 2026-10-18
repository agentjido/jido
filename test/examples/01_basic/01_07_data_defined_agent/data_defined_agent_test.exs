defmodule JidoTest.Examples.Basic.DataDefinedAgentTest do
  use JidoTest.Case, async: true
  @moduletag :example

  alias Jido.Agent
  alias Jido.Agent.Codec
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DataDefinedAgent, as: Example

  test "data and JSON definitions use the same direct and live contract", %{jido: jido} do
    {document, registry} = Example.encode()
    assert {:ok, definition} = Codec.decode(Jason.decode!(Jason.encode!(document)), registry)
    assert definition == Example.definition()
    direct = Agent.instantiate!(definition, id: unique_id("direct"))
    live = Agent.instantiate!(definition, id: unique_id("live"))
    {:ok, server} = JidoTest.ExampleRuntime.start_agent(jido, live)
    assert :ok = Server.await_ready(server)
    assert {:ok, candidate, []} = Agent.cmd(direct, Example.signal!(3))
    assert {:ok, committed, []} = Server.call(server, Example.signal!(3))
    assert candidate.state == %{count: 3, turns: 1}
    assert committed.state == candidate.state
  end

  test "a document cannot resolve references outside its trusted Registry" do
    {document, _registry} = Example.encode()
    assert {:error, _} = Codec.decode(document, %{})
  end
end
