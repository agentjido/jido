defmodule Jido.BehaviorTree.Nodes.AdditionalNodesTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Nodes.{Failer, Inverter, Repeat, SetBlackboard, Succeeder, Wait}
  alias Jido.BehaviorTree.{Tick, Blackboard}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode, RunningNode, ErrorNode}

  describe "Wait" do
    test "returns running initially" do
      wait = Wait.new(100)
      tick = Tick.new(Blackboard.new())

      {status, updated} = Wait.tick(wait, tick)
      assert status == :running
      assert updated.start_time != nil
    end

    test "returns success after duration" do
      wait = Wait.new(0)
      tick = Tick.new(Blackboard.new())

      {_status1, updated1} = Wait.tick(wait, tick)
      Process.sleep(1)
      {status2, _updated2} = Wait.tick(updated1, tick)
      assert status2 == :success
    end

    test "halt resets start time" do
      wait = %Wait{duration_ms: 100, start_time: 12345}
      halted = Wait.halt(wait)
      assert halted.start_time == nil
    end

    test "stays running while waiting" do
      wait = Wait.new(50)
      tick = Tick.new(Blackboard.new())

      {status1, updated1} = Wait.tick(wait, tick)
      assert status1 == :running

      {status2, _updated2} = Wait.tick(updated1, tick)
      assert status2 == :running
    end
  end

  describe "SetBlackboard" do
    test "sets single value" do
      node = SetBlackboard.new(:key, "value")
      tick = Tick.new(Blackboard.new())

      {status, updated} = SetBlackboard.tick(node, tick)
      assert status == :success
      assert Tick.get(updated.updated_tick, :key) == "value"
    end

    test "sets multiple values" do
      node = SetBlackboard.new(%{a: 1, b: 2})
      tick = Tick.new(Blackboard.new())

      {status, updated} = SetBlackboard.tick(node, tick)
      assert status == :success
      assert Tick.get(updated.updated_tick, :a) == 1
      assert Tick.get(updated.updated_tick, :b) == 2
    end

    test "halt clears updated_tick" do
      node = %SetBlackboard{entries: %{a: 1}, updated_tick: %{}}
      halted = SetBlackboard.halt(node)
      assert halted.updated_tick == nil
    end

    test "tick_with_context threads updated blackboard through returned tick" do
      node = SetBlackboard.new(%{flag: true})
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, updated_node, updated_tick} = SetBlackboard.tick_with_context(node, tick)

      assert status == :success
      assert Tick.get(updated_node.updated_tick, :flag) == true
      assert Tick.get(updated_tick, :flag) == true
    end
  end

  describe "Succeeder" do
    test "converts success to success" do
      succeeder = Succeeder.new(SimpleNode.new())
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Succeeder.tick(succeeder, tick)
      assert status == :success
    end

    test "converts failure to success" do
      succeeder = Succeeder.new(FailureNode.new())
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Succeeder.tick(succeeder, tick)
      assert status == :success
    end

    test "passes through running" do
      succeeder = Succeeder.new(RunningNode.new(3))
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Succeeder.tick(succeeder, tick)
      assert status == :running
    end

    test "passes through errors" do
      succeeder = Succeeder.new(ErrorNode.new("test error"))
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Succeeder.tick(succeeder, tick)
      assert status == {:error, "test error"}
    end

    test "halt propagates to child" do
      succeeder = Succeeder.new(RunningNode.new(3))
      tick = Tick.new(Blackboard.new())

      {_status, updated} = Succeeder.tick(succeeder, tick)
      halted = Succeeder.halt(updated)
      assert halted.child.tick_count == 0
    end

    test "tick_with_context preserves child tick blackboard updates" do
      succeeder = Succeeder.new(SetBlackboard.new(:decorator_key, "value"))
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, _updated, updated_tick} = Succeeder.tick_with_context(succeeder, tick)

      assert status == :success
      assert Tick.get(updated_tick, :decorator_key) == "value"
    end
  end

  describe "Failer" do
    test "converts success to failure" do
      failer = Failer.new(SimpleNode.new())
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Failer.tick(failer, tick)
      assert status == :failure
    end

    test "keeps failure as failure" do
      failer = Failer.new(FailureNode.new())
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Failer.tick(failer, tick)
      assert status == :failure
    end

    test "passes through running" do
      failer = Failer.new(RunningNode.new(3))
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Failer.tick(failer, tick)
      assert status == :running
    end

    test "passes through errors" do
      failer = Failer.new(ErrorNode.new("test error"))
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Failer.tick(failer, tick)
      assert status == {:error, "test error"}
    end

    test "halt propagates to child" do
      failer = Failer.new(RunningNode.new(3))
      tick = Tick.new(Blackboard.new())

      {_status, updated} = Failer.tick(failer, tick)
      halted = Failer.halt(updated)
      assert halted.child.tick_count == 0
    end

    test "tick_with_context preserves child tick blackboard updates" do
      failer = Failer.new(SetBlackboard.new(:failer_key, "value"))
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, _updated, updated_tick} = Failer.tick_with_context(failer, tick)

      assert status == :failure
      assert Tick.get(updated_tick, :failer_key) == "value"
    end
  end

  describe "Inverter" do
    test "inverts success to failure and preserves context updates" do
      inverter = Inverter.new(SetBlackboard.new(:inverter_key, "value"))
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status, _updated, updated_tick} = Inverter.tick_with_context(inverter, tick)

      assert status == :failure
      assert Tick.get(updated_tick, :inverter_key) == "value"
    end
  end

  describe "Repeat" do
    test "repeats child specified times" do
      repeat = Repeat.new(SimpleNode.new(), 3)
      tick = Tick.new(Blackboard.new())

      # First iteration
      {status1, updated1} = Repeat.tick(repeat, tick)
      assert status1 == :running
      assert updated1.current_iteration == 1

      # Second iteration
      {status2, updated2} = Repeat.tick(updated1, tick)
      assert status2 == :running
      assert updated2.current_iteration == 2

      # Third iteration - complete
      {status3, updated3} = Repeat.tick(updated2, tick)
      assert status3 == :success
      assert updated3.current_iteration == 0
    end

    test "fails immediately on child failure" do
      repeat = Repeat.new(FailureNode.new(), 5)
      tick = Tick.new(Blackboard.new())

      {status, updated} = Repeat.tick(repeat, tick)
      assert status == :failure
      assert updated.current_iteration == 0
    end

    test "passes through running" do
      repeat = Repeat.new(RunningNode.new(3), 2)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = Repeat.tick(repeat, tick)
      assert status == :running
    end

    test "passes through errors" do
      repeat = Repeat.new(ErrorNode.new("test error"), 3)
      tick = Tick.new(Blackboard.new())

      {status, updated} = Repeat.tick(repeat, tick)
      assert status == {:error, "test error"}
      assert updated.current_iteration == 0
    end

    test "halt resets iteration count" do
      repeat = %Repeat{child: SimpleNode.new(), count: 5, current_iteration: 3}
      halted = Repeat.halt(repeat)
      assert halted.current_iteration == 0
    end

    test "single repeat succeeds immediately" do
      repeat = Repeat.new(SimpleNode.new(), 1)
      tick = Tick.new(Blackboard.new())

      {status, updated} = Repeat.tick(repeat, tick)
      assert status == :success
      assert updated.current_iteration == 0
    end

    test "tick_with_context preserves child tick blackboard updates across iterations" do
      repeat = Repeat.new(SetBlackboard.new(:repeat_key, "value"), 2)
      tick = Tick.new_with_context(Blackboard.new(), nil, [], %{})

      {status1, updated1, tick1} = Repeat.tick_with_context(repeat, tick)
      assert status1 == :running
      assert Tick.get(tick1, :repeat_key) == "value"

      {status2, _updated2, tick2} = Repeat.tick_with_context(updated1, tick1)
      assert status2 == :success
      assert Tick.get(tick2, :repeat_key) == "value"
    end
  end
end
