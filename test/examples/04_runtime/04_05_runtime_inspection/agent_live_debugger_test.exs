defmodule JidoTest.Examples.Runtime.AgentLiveDebuggerTest do
  use JidoTest.FeatureSDKCase
  @moduletag :integration

  @moduletag group: :runtime
  @moduletag complexity: 3

  alias Jido.Examples.AgentLiveDebugger

  test "a snapshot uses public inspection and removes secrets", %{jido: jido} do
    agent = start_agent!(jido, AgentLiveDebugger, initial_state: %{secret_token: "secret"})
    assert {:ok, _} = AgentLiveDebugger.record_result(agent, input: %{result: "done"})

    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.agent_module == AgentLiveDebugger
    assert snapshot.state == %{status: "complete", result: "done"}
    assert snapshot.state_version == 1
    refute inspect(snapshot) =~ "secret"
  end

  test "inspection reads the committed state while an Action is still running", %{jido: jido} do
    {:ok, agent} = Jido.start_agent(jido, observed(AgentLiveDebugger, :on_work))
    task = Task.async(fn -> AgentLiveDebugger.record_result(agent, input: %{result: "later"}) end)
    assert_receive {:feature_work, worker, %{result: "later"}}, 1_000
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state == %{status: "idle", result: ""}
    assert snapshot.state_version == 0
    refute snapshot.runtime_status == :idle
    send(worker, :release)
    assert {:ok, _} = Task.await(task)
    snapshot = AgentLiveDebugger.snapshot(agent)
    assert snapshot.state.result == "later"
    assert snapshot.state_version == 1
  end
end
