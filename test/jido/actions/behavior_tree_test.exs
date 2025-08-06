defmodule JidoTest.Actions.BehaviorTreeTest do
  use ExUnit.Case, async: true

  alias Jido.Actions.BehaviorTree.{Tick, Succeed, Fail, Reset, GetCurrent}
  alias Jido.Agent.Directive.StateModification
  alias BehaviorTree.Node

  # Helper function to create mock action context
  defp action_context(state \\ %{}) do
    %{state: state}
  end

  describe "BehaviorTree.Tick" do
    test "starts a behavior tree and returns current behavior with state replacement" do
      tree = Node.sequence([:a, :b, :c])
      params = %{tree: tree, context: %{}, verbose: false}
      context = action_context(%{existing: "data"})
      
      assert {:ok, result, directives} = Tick.run(params, context)
      assert result.behavior == :a
      assert result.context == %{}
      assert is_struct(result.tree_state, BehaviorTree)
      
      # Check that we get a replace directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.op == :replace
      assert directive.path == []
      assert directive.value.tree_state == result.tree_state
      assert directive.value.context == %{}
      assert directive.value.existing == "data"  # Should preserve existing state
    end
  end

  describe "BehaviorTree.Succeed" do
    test "advances tree on success with state replacement" do
      tree = Node.sequence([:a, :b, :c])
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      context = action_context(%{tree_state: tree_state, context: %{}, other: "value"})
      
      assert {:ok, result, directives} = Succeed.run(params, context)
      assert result.behavior == :b  # Should advance to next in sequence
      assert is_struct(result.tree_state, BehaviorTree)
      
      # Check that we get a replace directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.op == :replace
      assert directive.path == []
      assert directive.value.tree_state == result.tree_state
      assert directive.value.context == %{}
      assert directive.value.other == "value"  # Should preserve existing state
    end
  end

  describe "BehaviorTree.Fail" do
    test "handles failure in tree with state replacement" do
      tree = Node.select([:a, :b, :c])  # Select tries next on failure
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      context = action_context(%{tree_state: tree_state, context: %{}, preserved: "data"})
      
      assert {:ok, result, directives} = Fail.run(params, context)
      assert result.behavior == :b  # Should try next option
      assert is_struct(result.tree_state, BehaviorTree)
      
      # Check that we get a replace directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.op == :replace
      assert directive.path == []
      assert directive.value.tree_state == result.tree_state
      assert directive.value.context == %{}
      assert directive.value.preserved == "data"  # Should preserve existing state
    end
  end

  describe "BehaviorTree.Reset" do
    test "resets tree to initial state with state replacement" do
      tree = Node.sequence([:a, :b, :c])
      params = %{tree: tree, context: %{reset: true}, verbose: false}
      context = action_context(%{existing: "state", other: "data"})
      
      assert {:ok, result, directives} = Reset.run(params, context)
      assert result.behavior == :a  # Should be back to first
      assert result.context == %{reset: true}
      assert is_struct(result.tree_state, BehaviorTree)
      
      # Check that we get a replace directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.op == :replace
      assert directive.path == []
      assert directive.value.tree_state == result.tree_state
      assert directive.value.context == %{reset: true}
      assert directive.value.existing == "state"  # Should preserve existing state
      assert directive.value.other == "data"  # Should preserve existing state
    end
  end

  describe "BehaviorTree.GetCurrent" do
    test "returns current behavior without advancing or state changes" do
      tree = Node.sequence([:a, :b, :c])
      tree_state = BehaviorTree.start(tree)
      
      params = %{tree_state: tree_state, context: %{}, verbose: false}
      context = action_context(%{tree_state: tree_state, context: %{}})
      
      assert {:ok, result} = GetCurrent.run(params, context)
      assert result.behavior == :a
      assert result.tree_state == tree_state  # Should be unchanged
      # GetCurrent shouldn't return directives since it doesn't modify state
    end
  end
end
