Code.require_file("hosted_agent.ex", __DIR__)

defmodule Jido.Examples.StartHere.HostedExpenseTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.Examples.StartHere.HostedExpense

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"start_here_hosted_#{suffix}"
    start_supervised!({Jido, name: instance}, id: instance)
    %{instance: instance}
  end

  test "AgentServer commits the same behavior as the pure Agent", %{instance: instance} do
    source = HostedExpense.instantiate!(id: "expense-hosted")
    {:ok, signal} = HostedExpense.submit_signal(%{report_id: "report-7", amount_cents: 12_500})
    assert {:ok, pure_candidate, []} = Jido.Agent.cmd(source, signal)

    assert {:ok, server} = Jido.start_agent(instance, source)
    assert :ok = AgentServer.await_ready(server)

    assert {:ok, %AgentServer.TurnResult{status: :committed, agent_revision: 1}} =
             AgentServer.call(server, signal)

    assert AgentServer.snapshot(server).agent == pure_candidate
  end

  test "a failed hosted Turn preserves committed state", %{instance: instance} do
    assert {:ok, server} = Jido.start_agent(instance, HostedExpense, id: "expense-hosted-invalid")
    assert :ok = AgentServer.await_ready(server)
    before = AgentServer.snapshot(server)
    {:ok, invalid} = HostedExpense.submit_signal(%{report_id: "", amount_cents: 0})

    assert {:ok, %AgentServer.TurnResult{status: :failed}} = AgentServer.call(server, invalid)
    assert AgentServer.snapshot(server) == before
  end
end
