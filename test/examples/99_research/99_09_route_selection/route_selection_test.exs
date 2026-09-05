defmodule JidoTest.Examples.RouteSelectionTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.RouteSelection, as: Example

  test "a single route produces equal direct and live state", %{jido: jido} do
    agent = Example.new(:single)
    signal = Example.signal("order.create")
    assert {:ok, candidate, []} = Jido.Agent.cmd(agent, signal)
    assert {:ok, server} = Jido.start_agent(jido, agent)
    assert {:ok, committed} = Jido.AgentServer.call(server, signal)
    assert candidate.state == committed.state
    assert committed.state.handler == "create"
  end

  test "an unmatched input reaches the fallback" do
    assert {:ok, agent, []} =
             Jido.Agent.cmd(Example.new(:fallback), Example.signal("other.input"))

    assert agent.state.handler == "fallback"
  end

  test "an exact route wins when wildcard routes also match" do
    assert {:ok, agent, []} =
             Jido.Agent.cmd(Example.new(:fallback), Example.signal("order.create"))

    assert agent.state.handler == "create"
  end

  test "preparation cannot replace the executable selected by the source Signal" do
    assert {:ok, agent, []} =
             Jido.Agent.cmd(Example.new(:rewrite), Example.signal("order.create"))

    assert agent.state.handler == "create"
  end
end
