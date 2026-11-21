defmodule Jido.BehaviorTree.Nodes.SelectorTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Nodes.Selector
  alias Jido.BehaviorTree.{Tick, Blackboard}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode, RunningNode}

  describe "new/1" do
    test "creates a selector with children" do
      children = [SimpleNode.new(), SimpleNode.new()]
      selector = Selector.new(children)

      assert %Selector{children: ^children, current_index: 0} = selector
    end

    test "creates an empty selector" do
      selector = Selector.new([])
      assert selector.children == []
    end
  end

  describe "tick/2" do
    test "succeeds immediately when first child succeeds" do
      children = [SimpleNode.new("a"), FailureNode.new(), SimpleNode.new("c")]
      selector = Selector.new(children)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = selector.__struct__.tick(selector, tick)
      assert status == :success
    end

    test "tries next child when one fails" do
      children = [FailureNode.new(), FailureNode.new(), SimpleNode.new()]
      selector = Selector.new(children)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = selector.__struct__.tick(selector, tick)
      assert status == :success
    end

    test "fails when all children fail" do
      children = [FailureNode.new(), FailureNode.new(), FailureNode.new()]
      selector = Selector.new(children)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = selector.__struct__.tick(selector, tick)
      assert status == :failure
    end

    test "returns running when a child is running" do
      children = [FailureNode.new(), RunningNode.new(3), SimpleNode.new()]
      selector = Selector.new(children)
      tick = Tick.new(Blackboard.new())

      {status, updated} = selector.__struct__.tick(selector, tick)
      assert status == :running
      assert updated.current_index == 1
    end

    test "resumes from running child" do
      children = [FailureNode.new(), RunningNode.new(2), SimpleNode.new()]
      selector = Selector.new(children)
      tick = Tick.new(Blackboard.new())

      # First tick - first fails, running node stays running
      {status1, updated1} = selector.__struct__.tick(selector, tick)
      assert status1 == :running
      assert updated1.current_index == 1

      # Second tick - running node completes with success
      {status2, _updated2} = updated1.__struct__.tick(updated1, tick)
      assert status2 == :success
    end

    test "empty selector returns failure" do
      selector = Selector.new([])
      tick = Tick.new(Blackboard.new())

      {status, _updated} = selector.__struct__.tick(selector, tick)
      assert status == :failure
    end
  end

  describe "tick_with_context/2" do
    test "returns success when a later child succeeds" do
      children = [FailureNode.new(), SimpleNode.new("ok")]
      selector = Selector.new(children)
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, _updated, updated_tick} = Selector.tick_with_context(selector, tick)

      assert status == :success
      assert updated_tick == tick
    end

    test "returns running and preserves index for running child" do
      children = [FailureNode.new(), RunningNode.new(2), SimpleNode.new()]
      selector = Selector.new(children)
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, updated, _updated_tick} = Selector.tick_with_context(selector, tick)

      assert status == :running
      assert updated.current_index == 1
    end
  end

  describe "halt/1" do
    test "halts all children and resets index" do
      children = [SimpleNode.new(), SimpleNode.new()]
      selector = %Selector{children: children, current_index: 1}

      halted = selector.__struct__.halt(selector)
      assert halted.current_index == 0
    end
  end

  describe "schema/0" do
    test "returns the Zoi schema" do
      assert %Zoi.Types.Struct{} = Selector.schema()
    end
  end
end
