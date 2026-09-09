defmodule JidoTest.Examples.Basic.DirectiveAgentTest do
  use JidoTest.BasicSDKCase

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.DirectiveAgent, as: Agent
  alias Jido.Examples.DirectiveAgent.Effects

  test "every handler observes committed state and dispatch follows batch order", %{jido: jido} do
    server = start_agent!(jido, Agent)
    %{pid: runtime} = Server.children(server)[{:plugin, Effects}]
    runtime_monitor = Process.monitor(runtime)
    server_monitor = Process.monitor(server)
    command = change(7, :valid)

    assert {:ok, committed} = Server.call(server, command)
    await_idle(server)
    records = Effects.records(server)

    assert Enum.map(records, & &1.label) == ["first", "second", "third"]

    for record <- records do
      assert record.snapshot == %{agent: committed, state_version: 1}
      assert record.context.state_version == 1
      assert record.context.agent_id == committed.id
      assert record.context.source_signal.id == command.id
    end

    assert records |> Enum.map(& &1.context.turn_id) |> Enum.uniq() |> length() == 1
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}

    assert :ok = Server.stop(server)
    assert_receive {:DOWN, ^runtime_monitor, :process, ^runtime, _reason}, 1_000
    assert_receive {:DOWN, ^server_monitor, :process, ^server, _reason}, 1_000
  end

  test "an invalid later Directive prevents the entire commit and all dispatch", %{jido: jido} do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    before = Server.snapshot(server)

    assert {:error, %Jido.Error.ValidationError{}} = Server.call(server, change(7, :invalid))

    await_idle(server)
    assert Server.snapshot(server) == before
    assert Effects.records(server) == []

    assert {:ok, recovered} = Server.call(server, change(2, :valid))
    await_idle(server)
    assert recovered.state.count == 2
    assert Server.snapshot(server) == %{agent: recovered, state_version: 1}
    assert Enum.map(Effects.records(server), & &1.label) == ["first", "second", "third"]
  end

  test "a failed second dispatch preserves the commit and prevents the third effect", %{
    jido: jido
  } do
    server = start_agent!(jido, Agent, error_policy: observe_errors())
    command = change(9, :dispatch_failure)

    assert {:ok, committed} = Server.call(server, command)
    assert_receive {:sdk_error, %Jido.Error.ExecutionError{}, outcome}, 1_000
    assert outcome.committed?
    assert outcome.source_signal.id == command.id
    await_idle(server)

    records = Effects.records(server)
    assert Enum.map(records, & &1.label) == ["first", "second"]
    assert Enum.all?(records, &(&1.snapshot == %{agent: committed, state_version: 1}))
    assert committed.state == %{count: 9}
    assert Server.snapshot(server) == %{agent: committed, state_version: 1}
  end

  defp change(count, batch), do: Agent.set_count_signal!(count, batch)
end
