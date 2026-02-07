defmodule JidoTest.Memory.MemoryTest do
  use ExUnit.Case, async: true

  alias Jido.Memory
  alias Jido.Memory.Space

  describe "new/0,1" do
    test "creates memory with default spaces" do
      memory = Memory.new()
      assert %Memory{} = memory
      assert Map.has_key?(memory.spaces, :world)
      assert Map.has_key?(memory.spaces, :tasks)
    end

    test "world space is a map space" do
      memory = Memory.new()
      assert Space.map?(memory.spaces.world)
      assert memory.spaces.world.data == %{}
    end

    test "tasks space is a list space" do
      memory = Memory.new()
      assert Space.list?(memory.spaces.tasks)
      assert memory.spaces.tasks.data == []
    end

    test "generates unique id with mem_ prefix" do
      memory = Memory.new()
      assert String.starts_with?(memory.id, "mem_")
    end

    test "accepts custom id" do
      memory = Memory.new(id: "custom-id")
      assert memory.id == "custom-id"
    end

    test "accepts metadata" do
      memory = Memory.new(metadata: %{agent_id: "a1"})
      assert memory.metadata == %{agent_id: "a1"}
    end

    test "initializes rev to 0" do
      memory = Memory.new()
      assert memory.rev == 0
    end

    test "sets timestamps" do
      memory = Memory.new()
      assert is_integer(memory.created_at)
      assert is_integer(memory.updated_at)
      assert memory.created_at == memory.updated_at
    end

    test "accepts custom timestamp" do
      memory = Memory.new(now: 1_000_000)
      assert memory.created_at == 1_000_000
      assert memory.updated_at == 1_000_000
    end
  end

  describe "reserved_spaces/0" do
    test "returns tasks and world" do
      assert :tasks in Memory.reserved_spaces()
      assert :world in Memory.reserved_spaces()
    end
  end

  describe "schema/0" do
    test "returns Zoi schema" do
      assert %{} = Memory.schema()
    end
  end
end
