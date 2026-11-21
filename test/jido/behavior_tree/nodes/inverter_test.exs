defmodule Jido.BehaviorTree.Nodes.InverterTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Nodes.Inverter
  alias Jido.BehaviorTree.{Tick, Blackboard}
  alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, FailureNode, RunningNode, ErrorNode}

  describe "new/1" do
    test "creates an inverter with child" do
      child = SimpleNode.new()
      inverter = Inverter.new(child)

      assert %Inverter{child: ^child} = inverter
    end
  end

  describe "tick/2" do
    test "inverts success to failure" do
      child = SimpleNode.new()
      inverter = Inverter.new(child)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = inverter.__struct__.tick(inverter, tick)
      assert status == :failure
    end

    test "inverts failure to success" do
      child = FailureNode.new()
      inverter = Inverter.new(child)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = inverter.__struct__.tick(inverter, tick)
      assert status == :success
    end

    test "passes through running status unchanged" do
      child = RunningNode.new(3)
      inverter = Inverter.new(child)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = inverter.__struct__.tick(inverter, tick)
      assert status == :running
    end

    test "passes through error status unchanged" do
      child = ErrorNode.new("test error")
      inverter = Inverter.new(child)
      tick = Tick.new(Blackboard.new())

      {status, _updated} = inverter.__struct__.tick(inverter, tick)
      assert {:error, "test error"} = status
    end

    test "updates child state" do
      child = RunningNode.new(2)
      inverter = Inverter.new(child)
      tick = Tick.new(Blackboard.new())

      {_status, updated} = inverter.__struct__.tick(inverter, tick)
      assert updated.child.tick_count == 1
    end
  end

  describe "halt/1" do
    test "halts the child" do
      child = %{SimpleNode.new() | tick_count: 5}
      inverter = Inverter.new(child)

      halted = inverter.__struct__.halt(inverter)
      assert halted.child.tick_count == 0
    end
  end

  describe "schema/0" do
    test "returns the Zoi schema" do
      assert %Zoi.Types.Struct{} = Inverter.schema()
    end
  end
end
