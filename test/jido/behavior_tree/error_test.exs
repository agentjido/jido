defmodule Jido.BehaviorTree.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Error

  describe "validation_error/2" do
    test "creates a BehaviorTreeError with validation type" do
      error = Error.validation_error("invalid input")

      assert %Error.BehaviorTreeError{} = error
      assert error.message == "invalid input"
      assert error.details.type == :validation
      assert error.class == :invalid
      assert error.splode == Error
    end

    test "includes additional details" do
      error = Error.validation_error("bad value", %{field: :name})

      assert error.details.field == :name
      assert error.details.type == :validation
    end
  end

  describe "execution_error/2" do
    test "creates a BehaviorTreeError with execution type" do
      error = Error.execution_error("action failed")

      assert %Error.BehaviorTreeError{} = error
      assert error.message == "action failed"
      assert error.details.type == :execution
      assert error.class == :execution
      assert error.splode == Error
    end
  end

  describe "node_error/3" do
    test "creates a BehaviorTreeError with node info" do
      error = Error.node_error("tick failed", MyNode, %{tick_count: 5})

      assert %Error.BehaviorTreeError{} = error
      assert error.message == "tick failed"
      assert error.details.type == :node
      assert error.details.node == MyNode
      assert error.details.tick_count == 5
      assert error.class == :execution
      assert error.splode == Error
    end
  end

  describe "BehaviorTreeError" do
    test "is an exception" do
      error = Error.BehaviorTreeError.exception(message: "test error")

      assert Exception.message(error) == "test error"
    end

    test "has default values" do
      error = Error.BehaviorTreeError.exception([])

      assert error.message == "Behavior tree error"
      assert error.details == %{}
      assert error.class == :execution
    end
  end
end
