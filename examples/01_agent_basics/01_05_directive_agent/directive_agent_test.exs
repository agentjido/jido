Code.require_file("effects.ex", __DIR__)
Code.require_file("directive_agent.ex", __DIR__)

defmodule Jido.Examples.Basic.DirectiveAgentTest do
  use Jido.Test.Agent.BasicSDKCase
  @moduletag :integration
  alias Jido.Examples.DirectiveAgent, as: Agent
  alias Jido.Examples.DirectiveAgent.Effects

  test "every handler observes committed state and dispatch follows batch order", %{jido: jido} do
    server = start_agent!(jido, Agent)
    id = Jido.AgentServer.snapshot(server).agent.id
    runtime = Effects.runtime(jido, id)
    runtime_monitor = Process.monitor(runtime)
    server_monitor = Process.monitor(server)
    command = change(7, :valid)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    await_idle(server)
    records = Effects.records(jido, Jido.AgentServer.snapshot(server).agent.id)

    assert Enum.map(records, & &1.label) == ["first", "second", "third"]

    for record <- records do
      assert record.snapshot.agent == committed
      assert record.snapshot.agent_revision == 1
      assert record.context.state_version == 1
      assert record.context.agent_id == committed.id
      assert record.context.source_signal.id == command.id
    end

    assert records |> Enum.map(& &1.context.turn_id) |> Enum.uniq() |> length() == 1
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == committed
    assert snapshot.agent_revision == 1

    assert {:ok, %Jido.AgentServer.Snapshot{}} = Jido.AgentServer.stop(server)
    assert_receive {:DOWN, ^runtime_monitor, :process, ^runtime, _reason}, 1_000
    assert_receive {:DOWN, ^server_monitor, :process, ^server, _reason}, 1_000
  end

  test "an invalid later Directive prevents the entire commit and all dispatch", %{jido: jido} do
    server = start_agent!(jido, Agent)
    before = Jido.AgentServer.snapshot(server)

    assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: %Jido.Error.ValidationError{}}} =
             Jido.AgentServer.call(server, change(7, :invalid))

    await_idle(server)
    assert Jido.AgentServer.snapshot(server) == before
    assert Effects.records(jido, Jido.AgentServer.snapshot(server).agent.id) == []

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, change(2, :valid))

      assert turn_result.status in [:committed, :waiting]
      recovered = Jido.AgentServer.snapshot(server).agent
    )

    await_idle(server)
    assert recovered.state.count == 2
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == recovered
    assert snapshot.agent_revision == 1

    assert Enum.map(Effects.records(jido, Jido.AgentServer.snapshot(server).agent.id), & &1.label) ==
             [
               "first",
               "second",
               "third"
             ]
  end

  test "a failed second dispatch preserves the commit and prevents the third effect", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent)
    command = change(9, :dispatch_failure)

    (
      assert {:ok, %Jido.AgentServer.TurnResult{} = turn_result} =
               Jido.AgentServer.call(server, command)

      assert turn_result.status in [:committed, :waiting]
      committed = Jido.AgentServer.snapshot(server).agent
    )

    await_idle(server)

    assert %{status: :succeeded, committed?: true} =
             Jido.AgentServer.status(server).last_outcome

    records = Effects.records(jido, Jido.AgentServer.snapshot(server).agent.id)
    assert Enum.map(records, & &1.label) == ["first", "second"]

    assert Enum.all?(
             records,
             &(&1.snapshot.agent == committed and &1.snapshot.agent_revision == 1)
           )

    assert committed.state == %{count: 9}
    snapshot = Jido.AgentServer.snapshot(server)
    assert snapshot.agent == committed
    assert snapshot.agent_revision == 1
  end

  defp change(count, batch) do
    {:ok, command_signal_1} = Agent.set_count_signal(%{count: count, batch: batch})
    command_signal_1
  end
end
