Code.require_file("notification.ex", __DIR__)
Code.require_file("runtime_inspection.ex", __DIR__)

defmodule Jido.Examples.StartHere.ObservedExpenseTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.StartHere.{ExpenseNotifications, ObservedExpense}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"start_here_observed_#{suffix}"
    table = :"start_here_observed_store_#{suffix}"
    namespace = "examples/start-here/observed/#{suffix}"

    start_supervised!(
      {Jido, name: instance, namespace: namespace, persistence: {Jido.Persistence.ETS, table: table}},
      id: instance
    )

    assert {:ok, server} =
             Jido.start_agent(instance, ObservedExpense,
               id: "expense-observed-#{suffix}",
               persistence: :inherit
             )

    assert :ok = AgentServer.await_ready(server)
    %{instance: instance, server: server}
  end

  test "public status shows wait, commit, effect, and the last failure", c do
    {:ok, request} =
      ObservedExpense.review_signal(%{report_id: "report-7", amount_cents: 12_500})

    assert {:ok, %AgentServer.TurnResult{status: :waiting, turn_id: turn_id, waits: waits}} =
             AgentServer.call(c.server, request)

    assert waits != []

    assert %AgentServer.Status{
             work_state: :waiting,
             active_turn_id: ^turn_id,
             waits: [_ | _]
           } = AgentServer.status(c.server)

    {:ok, approval} = ObservedExpense.decision_signal("report-7", :approve)

    assert {:ok, %AgentServer.TurnResult{status: :committed, turn_id: ^turn_id, effects: :pending}} =
             AgentServer.call(c.server, approval)

    assert {:ok, [notification]} = ExpenseNotifications.await(c.instance, c.server, 1)
    assert notification.status == :approved
    assert notification.snapshot.agent.state.status == :approved
    assert notification.snapshot.agent_revision == 1

    {:ok, invalid} = ObservedExpense.review_signal(%{report_id: "", amount_cents: 0})
    assert {:ok, %AgentServer.TurnResult{status: :failed}} = AgentServer.call(c.server, invalid)

    assert %AgentServer.Status{
             work_state: :idle,
             effects: :none,
             last_outcome: %{status: :failed, committed?: false}
           } = AgentServer.status(c.server)

    assert AgentServer.snapshot(c.server).agent.state.status == :approved
  end

  test "stopping the Agent stops its owned effect runtime", c do
    runtime = ExpenseNotifications.runtime(c.instance, c.server)
    monitor = Process.monitor(runtime)

    assert {:ok, %AgentServer.Snapshot{}} = AgentServer.stop(c.server)
    assert_receive {:DOWN, ^monitor, :process, ^runtime, _reason}, 1_000
  end
end
