defmodule JidoTest.Examples.Workflow.FlowDirectivesTest do
  use JidoTest.WorkflowSDKCase

  alias Jido.Examples.FlowDirectives, as: Example
  alias Jido.Examples.FlowDirectives.Effects

  test "a Flow returns every Directive in canonical component order" do
    agent = Example.new!(id: unique_id("flow-directives"))
    {:ok, signal} = Example.run_signal(%{})

    assert {:ok, candidate, directives} = Jido.Agent.cmd(agent, signal)
    assert candidate.state == %{count: 3}
    assert Enum.map(directives, & &1.label) == ["first", "side", "final"]
  end

  test "live dispatch starts after the single Agent commit", %{jido: jido} do
    server = start_agent!(jido, Example)
    {:ok, signal} = Example.run_signal(%{})
    assert {:ok, committed} = Jido.AgentServer.call(server, signal)

    eventually(fn -> length(Effects.records(server)) == 3 end)
    records = Effects.records(server)
    assert Enum.map(records, & &1.label) == ["first", "side", "final"]
    assert Enum.uniq_by(records, & &1.turn_id) |> length() == 1

    for record <- records do
      assert record.snapshot == %{agent: committed, state_version: 1}
    end
  end

  test "a later failure discards earlier Directives", %{jido: jido} do
    server = start_agent!(jido, Example)
    before = Jido.AgentServer.snapshot(server)
    {:ok, signal} = Example.fail_signal(%{})

    assert {:error, _reason} = Jido.Agent.cmd(before.agent, signal)
    assert {:error, _reason} = Jido.AgentServer.call(server, signal)
    eventually(fn -> Jido.AgentServer.status(server).phase == :idle end)
    assert Jido.AgentServer.snapshot(server) == before
    assert Effects.records(server) == []
  end
end
