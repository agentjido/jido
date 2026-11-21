defmodule Jido.BehaviorTree.StatusTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Status

  describe "success?/1" do
    test "returns true for :success" do
      assert Status.success?(:success)
    end

    test "returns false for other statuses" do
      refute Status.success?(:failure)
      refute Status.success?(:running)
      refute Status.success?({:error, "reason"})
    end
  end

  describe "failure?/1" do
    test "returns true for :failure" do
      assert Status.failure?(:failure)
    end

    test "returns true for error tuples" do
      assert Status.failure?({:error, "reason"})
    end

    test "returns false for other statuses" do
      refute Status.failure?(:success)
      refute Status.failure?(:running)
    end
  end

  describe "running?/1" do
    test "returns true for :running" do
      assert Status.running?(:running)
    end

    test "returns false for other statuses" do
      refute Status.running?(:success)
      refute Status.running?(:failure)
      refute Status.running?({:error, "reason"})
    end
  end

  describe "error?/1" do
    test "returns true for error tuples" do
      assert Status.error?({:error, "reason"})
    end

    test "returns false for other statuses" do
      refute Status.error?(:success)
      refute Status.error?(:failure)
      refute Status.error?(:running)
    end
  end

  describe "completed?/1" do
    test "returns true for success and failure" do
      assert Status.completed?(:success)
      assert Status.completed?(:failure)
      assert Status.completed?({:error, "reason"})
    end

    test "returns false for running" do
      refute Status.completed?(:running)
    end
  end

  describe "invert/1" do
    test "inverts success to failure" do
      assert Status.invert(:success) == :failure
    end

    test "inverts failure to success" do
      assert Status.invert(:failure) == :success
    end

    test "preserves running and error statuses" do
      assert Status.invert(:running) == :running
      assert Status.invert({:error, "reason"}) == {:error, "reason"}
    end
  end

  describe "from_action_result/1" do
    test "converts {:ok, result} to :success" do
      assert Status.from_action_result({:ok, %{data: "test"}}) == :success
    end

    test "converts {:error, reason} to {:error, reason}" do
      assert Status.from_action_result({:error, "failed"}) == {:error, "failed"}
    end
  end

  describe "from_boolean/1" do
    test "converts true to :success" do
      assert Status.from_boolean(true) == :success
    end

    test "converts false to :failure" do
      assert Status.from_boolean(false) == :failure
    end
  end
end
