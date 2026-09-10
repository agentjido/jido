defmodule JidoTest.Examples.PluginIsolationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.PluginIsolation, as: Example

  test "a Plugin updates its own state after a successful Action" do
    assert {:ok, candidate, []} = Jido.Agent.cmd(Example.new(), Example.signal())
    assert candidate.state.audit == 1
    assert candidate.state.total == 11
  end

  test "an Action cannot overwrite Plugin state and a failed live turn preserves state", %{
    jido: jido
  } do
    assert {:ok, server} = Jido.start_agent(jido, Example.new())
    before = Jido.AgentServer.snapshot(server)
    assert {:error, _} = Jido.AgentServer.call(server, Example.signal(%{overwrite_owned: true}))
    assert Jido.AgentServer.snapshot(server) == before
  end
end
