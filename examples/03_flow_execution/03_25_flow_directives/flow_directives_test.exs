Code.require_file("effects.ex", __DIR__)
Code.require_file("flow_directives.ex", __DIR__)

defmodule Jido.Examples.Workflow.FlowDirectivesTest do
  use Jido.Test.Agent.WorkflowSDKCase
  @moduletag :integration

  alias Jido.Examples.FlowDirectives, as: Example
  alias Jido.Examples.FlowDirectives.Effects

  test "a Flow returns every Directive in canonical component order" do
    agent = Example.instantiate!(id: unique_id("flow-directives"))
    {:ok, signal} = Example.run_signal(%{})

    assert {:ok, candidate, directives} = Jido.Agent.cmd(agent, signal)
    assert candidate.state == %{count: 3}
    assert Enum.map(directives, & &1.label) == ["first", "side", "final"]
  end

  test "live dispatch starts after the single Agent commit", %{jido: jido} do
    start_supervised!(Effects.registry_child_spec(jido))
    server = start_agent!(jido, Example)
    {:ok, signal} = Example.run_signal(%{})

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, signal)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    eventually(fn -> length(Effects.records(jido, server)) == 3 end)
    records = Effects.records(jido, server)
    assert Enum.map(records, & &1.label) == ["first", "side", "final"]
    assert Enum.uniq_by(records, & &1.turn_id) |> length() == 1

    for record <- records do
      assert record.snapshot.agent == committed
      assert record.snapshot.agent_revision == 1
    end
  end

  test "a later failure discards earlier Directives", %{jido: jido} do
    start_supervised!(Effects.registry_child_spec(jido))
    server = start_agent!(jido, Example)
    before = Jido.AgentServer.snapshot(server)
    {:ok, signal} = Example.fail_signal(%{})

    assert {:error, _reason} = Jido.Agent.cmd(before.agent, signal)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: _reason}} =
             Jido.AgentServer.call(server, signal)

    eventually(fn -> Jido.AgentServer.status(server).work_state == :idle end)
    assert Jido.AgentServer.snapshot(server) == before
    assert Effects.records(jido, server) == []
  end
end
