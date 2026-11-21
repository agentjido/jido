Code.require_file("behavior_tree.ex", __DIR__)

defmodule Jido.Examples.Applications.BehaviorTreeTest do
  use Jido.Test.Case, async: true

  @moduletag :integration

  alias Jido.AgentServer
  alias Jido.BehaviorTree.Blackboard
  alias Jido.Examples.Applications.BehaviorTree.Agent
  alias Jido.Signal

  test "a live Turn resumes the running tree and dispatches its Action effect after commit", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent, id: unique_id("tree"), default_dispatch: {:pid, target: self()})

    assert {:ok, %{status: :committed}} = AgentServer.call(server, Agent.bt_tick_signal!())
    assert %{reserved: 0, behavior_tree: %{status: :running, tick_count: 1}} = AgentServer.snapshot(server).agent.state
    refute_received {:signal, _}

    assert {:ok, %{status: :committed}} = AgentServer.call(server, Agent.bt_tick_signal!())
    assert_receive {:signal, %Signal{type: "examples.11.07.stock.reserved", data: %{reserved: 3}}}, 2_000

    assert %{reserved: 3, behavior_tree: %{status: :success, tick_count: 2, blackboard: blackboard}} =
             AgentServer.snapshot(server).agent.state

    assert Blackboard.get(blackboard, :last_result) == %{reserved: 3}

    assert {:ok, %{status: :committed}} = AgentServer.call(server, Agent.bt_reset_signal!())
    assert %{reserved: 3, behavior_tree: %{status: :idle, tick_count: 0}} = AgentServer.snapshot(server).agent.state

    monitor = Process.monitor(server)
    assert :ok = Jido.stop_agent(jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}
  end
end
