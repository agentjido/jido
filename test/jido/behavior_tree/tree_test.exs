defmodule Jido.BehaviorTree.TreeTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Tick, Tree}
  alias Jido.BehaviorTree.Nodes.{Selector, Sequence, SetBlackboard}
  alias Jido.BehaviorTree.Test.Nodes.{FailureNode, RunningNode, SimpleNode}

  test "tick_with_context/2 threads updated tick from root node" do
    tree = Tree.new(SetBlackboard.new(:result, :ok))
    tick = Tick.new_with_context(Tick.new().blackboard, nil, [], %{})

    {status, _updated_tree, updated_tick} = Tree.tick_with_context(tree, tick)

    assert status == :success
    assert Tick.get(updated_tick, :result) == :ok
  end

  test "tick_with_context/2 threads blackboard updates through composite nodes" do
    tree =
      Tree.new(
        Sequence.new([
          SetBlackboard.new(:composite_result, :ok),
          SimpleNode.new("done")
        ])
      )

    tick = Tick.new_with_context(Tick.new().blackboard, nil, [], %{})
    {status, _updated_tree, updated_tick} = Tree.tick_with_context(tree, tick)

    assert status == :success
    assert Tick.get(updated_tick, :composite_result) == :ok
  end

  test "halt/1 traverses child nodes and resets running state" do
    sequence = Sequence.new([RunningNode.new(10), SimpleNode.new("done")])
    tree = Tree.new(sequence)
    tick = Tick.new()

    {:running, running_tree} = Tree.tick(tree, tick)
    halted_tree = Tree.halt(running_tree)

    [running_child | _] = halted_tree.root.children
    assert running_child.tick_count == 0
    assert halted_tree.root.current_index == 0
  end

  test "valid?/1 returns true for valid trees" do
    assert Tree.valid?(Tree.new(SimpleNode.new("valid")))
  end

  test "depth/1 and node_count/1 return tree topology values" do
    tree =
      Tree.new(
        Sequence.new([
          SimpleNode.new("a"),
          Selector.new([FailureNode.new("no"), SimpleNode.new("b")])
        ])
      )

    assert Tree.depth(tree) == 3
    assert Tree.node_count(tree) == 5
  end

  test "traverse/2 updates each node in the tree" do
    tree =
      Tree.new(
        Sequence.new([
          SimpleNode.new("a"),
          SimpleNode.new("b")
        ])
      )

    updated_tree =
      Tree.traverse(tree, fn node ->
        case node do
          %SimpleNode{} -> %{node | data: "updated"}
          other -> other
        end
      end)

    [first, second] = updated_tree.root.children
    assert first.data == "updated"
    assert second.data == "updated"
  end
end
