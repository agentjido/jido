defmodule Jido.BehaviorTree.Nodes.SequenceTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Nodes.Sequence
  alias Jido.BehaviorTree.{Tick, Blackboard}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode, RunningNode}

  describe "new/1" do
    test "creates a sequence with children" do
      children = [SimpleNode.new(), SimpleNode.new()]
      sequence = Sequence.new(children)

      assert %Sequence{children: ^children, current_index: 0} = sequence
    end

    test "creates an empty sequence" do
      sequence = Sequence.new([])
      assert sequence.children == []
    end
  end

  describe "tick/2" do
    test "succeeds when all children succeed" do
      children = [SimpleNode.new("a"), SimpleNode.new("b"), SimpleNode.new("c")]
      sequence = Sequence.new(children)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = sequence.__struct__.tick(sequence, tick)
      assert status == :success
    end

    test "fails immediately when a child fails" do
      children = [SimpleNode.new(), FailureNode.new(), SimpleNode.new()]
      sequence = Sequence.new(children)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = sequence.__struct__.tick(sequence, tick)
      assert status == :failure
    end

    test "returns running when a child is running" do
      children = [SimpleNode.new(), RunningNode.new(3), SimpleNode.new()]
      sequence = Sequence.new(children)
      tick = Tick.new(Blackboard.new())

      {status, updated} = sequence.__struct__.tick(sequence, tick)
      assert status == :running
      assert updated.current_index == 1
    end

    test "resumes from running child" do
      children = [SimpleNode.new(), RunningNode.new(2), SimpleNode.new()]
      sequence = Sequence.new(children)
      tick = Tick.new(Blackboard.new())

      # First tick - runs first child, then running node stays running
      {status1, updated1} = sequence.__struct__.tick(sequence, tick)
      assert status1 == :running
      assert updated1.current_index == 1

      # Second tick - running node completes, third child runs
      {status2, _updated2} = updated1.__struct__.tick(updated1, tick)
      assert status2 == :success
    end

    test "empty sequence returns success" do
      sequence = Sequence.new([])
      tick = Tick.new(Blackboard.new())

      {status, _updated} = sequence.__struct__.tick(sequence, tick)
      assert status == :success
    end
  end

  describe "tick_with_context/2" do
    test "threads updated tick and returns success when all children succeed" do
      children = [SimpleNode.new("a"), SimpleNode.new("b")]
      sequence = Sequence.new(children)
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, _updated, updated_tick} = Sequence.tick_with_context(sequence, tick)

      assert status == :success
      assert updated_tick == tick
    end

    test "returns running with current index when child is running" do
      children = [SimpleNode.new(), RunningNode.new(3), SimpleNode.new()]
      sequence = Sequence.new(children)
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, updated, _updated_tick} = Sequence.tick_with_context(sequence, tick)

      assert status == :running
      assert updated.current_index == 1
    end
  end

  describe "halt/1" do
    test "halts all children and resets index" do
      children = [SimpleNode.new(), SimpleNode.new()]
      sequence = %Sequence{children: children, current_index: 1}

      halted = sequence.__struct__.halt(sequence)
      assert halted.current_index == 0
    end
  end

  describe "schema/0" do
    test "returns the Zoi schema" do
      assert is_struct(Sequence.schema())
    end
  end
end
