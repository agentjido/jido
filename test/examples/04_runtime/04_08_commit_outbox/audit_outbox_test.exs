defmodule JidoTest.Examples.Runtime.AuditOutboxTest do
  use JidoTest.AgentCase

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.AuditOutbox
  alias Jido.Examples.AuditOutbox.MemorySink

  test "failed work creates no audit intent and dispatch is idempotent", %{jido: jido} do
    quiet_error_policy = fn _reason, _outcome -> :continue end
    agent = start_agent!(jido, AuditOutbox, error_policy: quiet_error_policy)
    sink = start_supervised!(MemorySink)

    assert {:ok, changed} =
             AuditOutbox.adjust_balance(agent, input: %{command_id: "command-1", amount: 10})

    assert length(changed.state.audit_outbox) == 1

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             AuditOutbox.adjust_balance(agent, input: %{command_id: "command-2", amount: -20})

    assert :ok = AuditOutbox.dispatch(agent, sink)
    assert :ok = AuditOutbox.dispatch(agent, sink)
    assert [%{id: "command-1"}] = Enum.map(MemorySink.records(sink), &Map.take(&1, [:id]))
  end

  test "a duplicate command cannot change the balance behind a deduplicated audit record", %{
    jido: jido
  } do
    agent = start_agent!(jido, AuditOutbox, error_policy: :log_only)
    assert {:ok, _} = AuditOutbox.adjust_balance(agent, input: %{command_id: "same", amount: 10})
    before = Jido.AgentServer.snapshot(agent)

    for amount <- [10, 99] do
      assert {:error, _} =
               AuditOutbox.adjust_balance(agent, input: %{command_id: "same", amount: amount})

      assert Jido.AgentServer.snapshot(agent) == before
    end
  end

  test "undelivered intent survives Agent restore and can be dispatched again", %{jido: jido} do
    id = unique_id("outbox")
    persistence = {Jido.Persistence.ETS, table: :"outbox_#{System.unique_integer([:positive])}"}
    agent = start_agent!(jido, AuditOutbox, id: id, persistence: persistence, restore: false)
    assert {:ok, _} = AuditOutbox.adjust_balance(agent, input: %{command_id: "a", amount: 10})
    assert {:ok, _} = AuditOutbox.adjust_balance(agent, input: %{command_id: "b", amount: -3})
    sink = start_supervised!(MemorySink)
    assert MemorySink.records(sink) == []
    ref = Process.monitor(agent)
    assert :ok = Jido.AgentServer.hibernate(agent)
    assert_receive {:DOWN, ^ref, :process, ^agent, _}, 1_000
    assert {:ok, restored} = Jido.thaw(jido, AuditOutbox, id, persistence: persistence)
    assert :ok = AuditOutbox.dispatch(restored, sink)
    assert :ok = AuditOutbox.dispatch(restored, sink)

    assert Enum.map(MemorySink.records(sink), &{&1.id, &1.resulting_balance}) == [
             {"a", 10},
             {"b", 7}
           ]

    assert agent_result(restored).state.balance == 7
  end
end
