defmodule Jido.BehaviorTreeTest do
  use ExUnit.Case
  doctest Jido.BehaviorTree

  alias Jido.BehaviorTree
  alias Jido.BehaviorTree.Blackboard
  alias Jido.BehaviorTree.Test.Nodes.SimpleNode

  test "creates new behavior tree" do
    node = SimpleNode.new("test")
    tree = BehaviorTree.new(node)

    assert %BehaviorTree.Tree{} = tree
    assert BehaviorTree.Tree.root(tree) == node
  end

  test "executes behavior tree tick" do
    node = SimpleNode.new("test")
    tree = BehaviorTree.new(node)
    tick = BehaviorTree.tick()

    {status, updated_tree} = BehaviorTree.tick(tree, tick)

    assert status == :success
    assert %BehaviorTree.Tree{} = updated_tree

    # Verify the node was ticked
    updated_node = BehaviorTree.Tree.root(updated_tree)
    assert updated_node.tick_count == 1
  end

  test "blackboard/1 and tick/1 constructors work together" do
    blackboard = BehaviorTree.blackboard(%{value: 1})
    tick = BehaviorTree.tick(blackboard)

    assert %Blackboard{} = blackboard
    assert BehaviorTree.Tick.get(tick, :value) == 1
  end

  test "start_agent/1 delegates to agent module" do
    tree = BehaviorTree.new(SimpleNode.new("agent"))
    {:ok, agent} = BehaviorTree.start_agent(tree: tree)

    assert is_pid(agent)
    assert :success == BehaviorTree.Agent.tick(agent)

    GenServer.stop(agent)
  end

  test "skill/4 creates executable skill wrapper" do
    tree = BehaviorTree.new(SimpleNode.new("skill"))
    skill = BehaviorTree.skill("bt_skill", tree, "skill")

    assert skill.name == "bt_skill"
    assert {:ok, result} = BehaviorTree.Skill.run(skill, %{}, %{})
    assert is_map(result)
  end
end
