defmodule JidoTest.Actions.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.BehaviorTree.{Tick, Succeed, Fail, Reset, GetCurrent}
  alias BehaviorTree.Node

  describe "BehaviorTree.Tick" do
    test "starts a behavior tree and returns current behavior" do
      tree = Node.sequence([:a, :b, :c])
      params = %{tree: tree, context: %{}, verbose: false}
      
      assert {:ok, result} = Tick.run(params)
      assert result.behavior == :a
      assert result.context == %{}
      assert is_struct(result.tree_state, BehaviorTree)
    end
  end

  describe "BehaviorTree.Succeed" do
    test "advances tree on success" do
      tree = Node.sequence([:a, :b, :c])
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      
      assert {:ok, result} = Succeed.run(params)
      assert result.behavior == :b  # Should advance to next in sequence
      assert is_struct(result.tree_state, BehaviorTree)
    end
  end

  describe "BehaviorTree.Fail" do
    test "handles failure in tree" do
      tree = Node.select([:a, :b, :c])  # Select tries next on failure
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      
      assert {:ok, result} = Fail.run(params)
      assert result.behavior == :b  # Should try next option
      assert is_struct(result.tree_state, BehaviorTree)
    end
  end

  describe "BehaviorTree.Reset" do
    test "resets tree to initial state" do
      tree = Node.sequence([:a, :b, :c])
      params = %{tree: tree, context: %{reset: true}, verbose: false}
      
      assert {:ok, result} = Reset.run(params)
      assert result.behavior == :a  # Should be back to first
      assert result.context == %{reset: true}
      assert is_struct(result.tree_state, BehaviorTree)
    end
  end

  describe "BehaviorTree.GetCurrent" do
    test "returns current behavior without advancing" do
      tree = Node.sequence([:a, :b, :c])
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      
      assert {:ok, result} = GetCurrent.run(params)
      assert result.behavior == :a
      assert result.tree_state == tree_state  # Should be unchanged
    end
  end
end
