defmodule JidoTest.Actions.SimplebotTest do
  use ExUnit.Case, async: true
  alias Jido.Actions.Simplebot

  describe "Move" do
    test "moves the robot to the specified destination" do
      params = %{destination: :kitchen}
      assert {:ok, result} = Simplebot.Move.run(params, %{sleep: 10})
      assert result.location == :kitchen
    end
  end

  describe "Idle" do
    test "does nothing and returns the same params" do
      params = %{some: :data}
      assert {:ok, ^params} = Simplebot.Idle.run(params, %{sleep: 10})
    end
  end

  describe "DoWork" do
    test "decreases battery level" do
      params = %{battery_level: 100}
      assert {:ok, result} = Simplebot.DoWork.run(params, %{sleep: 10})
      assert result.battery_level < 100
      # Minimum possible value after work
      assert result.battery_level >= 75
    end

    test "doesn't decrease battery level below 0" do
      params = %{battery_level: 10}
      assert {:ok, result} = Simplebot.DoWork.run(params, %{sleep: 10})
      assert result.battery_level >= 0
    end
  end

  describe "Report" do
    test "marks the robot as having reported" do
      params = %{has_reported: false}
      assert {:ok, result} = Simplebot.Report.run(params, %{sleep: 10})
      assert result.has_reported == true
    end
  end

  describe "Recharge" do
    test "increases battery level" do
      params = %{battery_level: 50}
      assert {:ok, result} = Simplebot.Recharge.run(params, %{sleep: 10})
      assert result.battery_level > 50
      assert result.battery_level <= 100
    end

    test "doesn't increase battery level above 100" do
      params = %{battery_level: 90}
      assert {:ok, result} = Simplebot.Recharge.run(params, %{sleep: 10})
      assert result.battery_level <= 100
    end
  end
end
