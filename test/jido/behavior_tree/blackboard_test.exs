defmodule Jido.BehaviorTree.BlackboardTest do
  use ExUnit.Case, async: true

  alias Jido.BehaviorTree.Blackboard

  describe "new/1" do
    test "creates empty blackboard with no initial data" do
      bb = Blackboard.new()
      assert bb.data == %{}
    end

    test "creates blackboard with initial data" do
      initial = %{user_id: 123, status: "active"}
      bb = Blackboard.new(initial)
      assert bb.data == initial
    end
  end

  describe "get/3" do
    test "gets existing value" do
      bb = Blackboard.new(%{key: "value"})
      assert Blackboard.get(bb, :key) == "value"
    end

    test "returns nil for missing key with no default" do
      bb = Blackboard.new()
      assert Blackboard.get(bb, :missing) == nil
    end

    test "returns default for missing key" do
      bb = Blackboard.new()
      assert Blackboard.get(bb, :missing, "default") == "default"
    end
  end

  describe "put/3" do
    test "sets new value" do
      bb = Blackboard.new()
      updated_bb = Blackboard.put(bb, :key, "value")
      assert Blackboard.get(updated_bb, :key) == "value"
    end

    test "overwrites existing value" do
      bb = Blackboard.new(%{key: "old"})
      updated_bb = Blackboard.put(bb, :key, "new")
      assert Blackboard.get(updated_bb, :key) == "new"
    end
  end

  describe "update/4" do
    test "updates existing value" do
      bb = Blackboard.new(%{counter: 5})
      updated_bb = Blackboard.update(bb, :counter, 0, &(&1 + 1))
      assert Blackboard.get(updated_bb, :counter) == 6
    end

    test "uses initial value for missing key" do
      bb = Blackboard.new()
      updated_bb = Blackboard.update(bb, :counter, 0, &(&1 + 1))
      assert Blackboard.get(updated_bb, :counter) == 1
    end
  end

  describe "delete/2" do
    test "removes existing key" do
      bb = Blackboard.new(%{key: "value", other: "data"})
      updated_bb = Blackboard.delete(bb, :key)
      assert Blackboard.get(updated_bb, :key) == nil
      assert Blackboard.get(updated_bb, :other) == "data"
    end

    test "handles missing key gracefully" do
      bb = Blackboard.new(%{key: "value"})
      updated_bb = Blackboard.delete(bb, :missing)
      assert Blackboard.get(updated_bb, :key) == "value"
    end
  end

  describe "has_key?/2" do
    test "returns true for existing key" do
      bb = Blackboard.new(%{key: "value"})
      assert Blackboard.has_key?(bb, :key)
    end

    test "returns false for missing key" do
      bb = Blackboard.new()
      refute Blackboard.has_key?(bb, :missing)
    end
  end

  describe "keys/1" do
    test "returns all keys" do
      bb = Blackboard.new(%{a: 1, b: 2})
      keys = Blackboard.keys(bb)
      assert Enum.sort(keys) == [:a, :b]
    end

    test "returns empty list for empty blackboard" do
      bb = Blackboard.new()
      assert Blackboard.keys(bb) == []
    end
  end

  describe "values/1" do
    test "returns all values" do
      bb = Blackboard.new(%{a: 1, b: 2})
      values = Blackboard.values(bb)
      assert Enum.sort(values) == [1, 2]
    end

    test "returns empty list for empty blackboard" do
      bb = Blackboard.new()
      assert Blackboard.values(bb) == []
    end
  end

  describe "merge/2" do
    test "merges two blackboards" do
      bb1 = Blackboard.new(%{a: 1, b: 2})
      bb2 = Blackboard.new(%{b: 3, c: 4})
      merged = Blackboard.merge(bb1, bb2)

      assert Blackboard.get(merged, :a) == 1
      # bb2 value wins
      assert Blackboard.get(merged, :b) == 3
      assert Blackboard.get(merged, :c) == 4
    end

    test "merges blackboard with plain map" do
      bb = Blackboard.new(%{a: 1})
      map = %{b: 2, c: 3}
      merged = Blackboard.merge(bb, map)

      assert Blackboard.get(merged, :a) == 1
      assert Blackboard.get(merged, :b) == 2
      assert Blackboard.get(merged, :c) == 3
    end
  end

  describe "to_map/1" do
    test "converts blackboard to plain map" do
      bb = Blackboard.new(%{a: 1, b: 2})
      map = Blackboard.to_map(bb)
      assert map == %{a: 1, b: 2}
    end
  end

  describe "size/1" do
    test "returns number of keys" do
      bb = Blackboard.new(%{a: 1, b: 2, c: 3})
      assert Blackboard.size(bb) == 3
    end

    test "returns 0 for empty blackboard" do
      bb = Blackboard.new()
      assert Blackboard.size(bb) == 0
    end
  end

  describe "empty?/1" do
    test "returns true for empty blackboard" do
      bb = Blackboard.new()
      assert Blackboard.empty?(bb)
    end

    test "returns false for non-empty blackboard" do
      bb = Blackboard.new(%{a: 1})
      refute Blackboard.empty?(bb)
    end
  end
end
