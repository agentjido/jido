defmodule JidoTest.Examples.PluginIsolationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.PluginIsolation, as: Example

  test "a Plugin updates its own state after a successful Action" do
    assert {:ok, candidate, []} = Jido.Agent.cmd(Example.new(), Example.signal())
    assert candidate.state.audit == 1
    assert candidate.state.total == 10
    assert candidate.state.first_input == "original"
  end

  test "an Action cannot overwrite Plugin state and a failed live turn preserves state", %{
    jido: jido
  } do
    assert {:ok, server} = Jido.start_agent(jido, Example.new())
    before = Jido.AgentServer.snapshot(server)
    assert {:error, _} = Jido.AgentServer.call(server, Example.signal(%{overwrite_owned: true}))
    assert Jido.AgentServer.snapshot(server) == before
  end

  test "the audit callback can observe only its intended total field" do
    assert {:ok, candidate, []} = Jido.Agent.cmd(Example.new(), Example.signal())
    assert candidate.state.observed_fields == [:total]
  end

  test "a later Plugin cannot replace an earlier Plugin's prepared input" do
    assert {:ok, candidate, []} =
             Jido.Agent.cmd(Example.new(replace_input: true), Example.signal())

    assert candidate.state.first_input == "original"
  end
end
