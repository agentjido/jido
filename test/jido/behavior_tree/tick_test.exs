defmodule Jido.BehaviorTree.TickTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.{Blackboard, Tick}

  describe "new/1" do
    test "creates tick with empty blackboard" do
      tick = Tick.new()
      assert %Tick{} = tick
      assert tick.sequence == 0
      assert Blackboard.empty?(tick.blackboard)
    end

    test "creates tick with provided blackboard" do
      bb = Blackboard.new(%{user_id: 123})
      tick = Tick.new(bb)
      assert tick.blackboard == bb
      assert tick.sequence == 0
    end
  end

  describe "new/3" do
    test "creates tick with all parameters" do
      bb = Blackboard.new(%{test: "data"})
      timestamp = DateTime.utc_now()
      sequence = 5

      tick = Tick.new(bb, timestamp, sequence)
      assert tick.blackboard == bb
      assert tick.timestamp == timestamp
      assert tick.sequence == sequence
    end
  end

  describe "update_blackboard/2" do
    test "updates the blackboard" do
      tick = Tick.new()
      new_bb = Blackboard.new(%{updated: true})
      updated_tick = Tick.update_blackboard(tick, new_bb)

      assert updated_tick.blackboard == new_bb
      assert updated_tick.sequence == tick.sequence
      assert updated_tick.timestamp == tick.timestamp
    end
  end

  describe "increment_sequence/1" do
    test "increments the sequence number" do
      tick = Tick.new()
      updated_tick = Tick.increment_sequence(tick)
      assert updated_tick.sequence == 1
    end

    test "preserves other fields" do
      bb = Blackboard.new(%{test: "data"})
      tick = Tick.new(bb)
      updated_tick = Tick.increment_sequence(tick)

      assert updated_tick.blackboard == bb
      assert updated_tick.timestamp == tick.timestamp
    end
  end

  describe "get/3" do
    test "gets value from blackboard" do
      bb = Blackboard.new(%{key: "value"})
      tick = Tick.new(bb)
      assert Tick.get(tick, :key) == "value"
    end

    test "returns default for missing key" do
      tick = Tick.new()
      assert Tick.get(tick, :missing, "default") == "default"
    end
  end

  describe "put/3" do
    test "sets value in blackboard and returns updated tick" do
      tick = Tick.new()
      updated_tick = Tick.put(tick, :key, "value")
      assert Tick.get(updated_tick, :key) == "value"
    end

    test "preserves other tick fields" do
      tick = Tick.new()
      original_timestamp = tick.timestamp
      original_sequence = tick.sequence

      updated_tick = Tick.put(tick, :key, "value")
      assert updated_tick.timestamp == original_timestamp
      assert updated_tick.sequence == original_sequence
    end
  end

  describe "update/4" do
    test "updates value in blackboard" do
      bb = Blackboard.new(%{counter: 5})
      tick = Tick.new(bb)
      updated_tick = Tick.update(tick, :counter, 0, &(&1 + 1))
      assert Tick.get(updated_tick, :counter) == 6
    end

    test "uses initial value for missing key" do
      tick = Tick.new()
      updated_tick = Tick.update(tick, :counter, 0, &(&1 + 1))
      assert Tick.get(updated_tick, :counter) == 1
    end
  end

  describe "elapsed_time/1" do
    test "returns elapsed time in milliseconds" do
      tick = Tick.new()
      Process.sleep(10)
      elapsed = Tick.elapsed_time(tick)
      assert elapsed >= 10
      # Should be reasonable
      assert elapsed < 1000
    end
  end

  describe "timed_out?/2" do
    test "returns false when under timeout" do
      tick = Tick.new()
      refute Tick.timed_out?(tick, 1000)
    end

    test "returns true when over timeout" do
      # Create a tick with an old timestamp
      old_timestamp = DateTime.add(DateTime.utc_now(), -2000, :millisecond)
      bb = Blackboard.new()
      tick = Tick.new(bb, old_timestamp, 0)

      assert Tick.timed_out?(tick, 1000)
    end
  end
end
