defmodule JidoTest.Memory.AgentTest do
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Memory
  alias Jido.Memory.Agent, as: MemoryAgent
  alias Jido.Memory.Space

  defp create_agent do
    %Agent{
      id: "test-agent-1",
      state: %{}
    }
  end

  describe "key/0" do
    test "returns :__memory__" do
      assert MemoryAgent.key() == :__memory__
    end
  end

  describe "get/2" do
    test "returns nil when no memory present" do
      agent = create_agent()
      assert MemoryAgent.get(agent) == nil
    end

    test "returns default when no memory present" do
      agent = create_agent()
      default = Memory.new()
      assert MemoryAgent.get(agent, default) == default
    end

    test "returns memory when present" do
      memory = Memory.new(id: "test-mem")
      agent = %{create_agent() | state: %{__memory__: memory}}
      assert MemoryAgent.get(agent) == memory
    end
  end

  describe "put/2" do
    test "stores memory in agent state" do
      agent = create_agent()
      memory = Memory.new(id: "test-mem")

      updated = MemoryAgent.put(agent, memory)

      assert updated.state[:__memory__] == memory
      assert MemoryAgent.get(updated) == memory
    end

    test "preserves other state keys" do
      agent = %{create_agent() | state: %{foo: :bar}}
      memory = Memory.new()

      updated = MemoryAgent.put(agent, memory)

      assert updated.state[:foo] == :bar
      assert updated.state[:__memory__] == memory
    end
  end

  describe "update/2" do
    test "updates memory using function" do
      memory = Memory.new(id: "test-mem")
      agent = MemoryAgent.put(create_agent(), memory)

      updated =
        MemoryAgent.update(agent, fn m ->
          %{m | metadata: %{updated: true}}
        end)

      result = MemoryAgent.get(updated)
      assert result.metadata == %{updated: true}
    end

    test "passes nil to function when no memory" do
      agent = create_agent()

      updated =
        MemoryAgent.update(agent, fn m ->
          assert m == nil
          Memory.new(id: "created-in-update")
        end)

      assert MemoryAgent.get(updated).id == "created-in-update"
    end
  end

  describe "ensure/2" do
    test "creates memory if missing" do
      agent = create_agent()
      assert MemoryAgent.has_memory?(agent) == false

      updated = MemoryAgent.ensure(agent)

      assert MemoryAgent.has_memory?(updated) == true
      assert %Memory{} = MemoryAgent.get(updated)
    end

    test "initializes with world and tasks spaces" do
      agent = MemoryAgent.ensure(create_agent())
      memory = MemoryAgent.get(agent)

      assert Map.has_key?(memory.spaces, :world)
      assert Map.has_key?(memory.spaces, :tasks)
      assert Space.map?(memory.spaces.world)
      assert Space.list?(memory.spaces.tasks)
    end

    test "does NOT overwrite existing memory" do
      memory = Memory.new(id: "original", metadata: %{keep: :this})
      agent = MemoryAgent.put(create_agent(), memory)

      updated = MemoryAgent.ensure(agent, metadata: %{new: :data})

      result = MemoryAgent.get(updated)
      assert result.id == "original"
      assert result.metadata == %{keep: :this}
    end

    test "passes options to Memory.new" do
      agent = MemoryAgent.ensure(create_agent(), metadata: %{user_id: "u1"})
      memory = MemoryAgent.get(agent)
      assert memory.metadata == %{user_id: "u1"}
    end
  end

  describe "has_memory?/1" do
    test "returns false when no memory" do
      assert MemoryAgent.has_memory?(create_agent()) == false
    end

    test "returns true when memory present" do
      agent = MemoryAgent.put(create_agent(), Memory.new())
      assert MemoryAgent.has_memory?(agent) == true
    end
  end

  describe "space/2" do
    test "returns nil when no memory" do
      assert MemoryAgent.space(create_agent(), :world) == nil
    end

    test "returns space when present" do
      agent = MemoryAgent.ensure(create_agent())
      space = MemoryAgent.space(agent, :world)
      assert %Space{} = space
      assert Space.map?(space)
    end

    test "returns nil for non-existent space" do
      agent = MemoryAgent.ensure(create_agent())
      assert MemoryAgent.space(agent, :nonexistent) == nil
    end
  end

  describe "put_space/3" do
    test "stores space" do
      agent = MemoryAgent.ensure(create_agent())
      space = Space.new_kv(data: %{custom: true})

      updated = MemoryAgent.put_space(agent, :custom, space)

      result = MemoryAgent.space(updated, :custom)
      assert result.data == %{custom: true}
    end

    test "bumps container rev" do
      agent = MemoryAgent.ensure(create_agent())
      initial_rev = MemoryAgent.get(agent).rev

      updated = MemoryAgent.put_space(agent, :custom, Space.new_kv())

      assert MemoryAgent.get(updated).rev == initial_rev + 1
    end

    test "accepts injectable timestamp" do
      agent = MemoryAgent.ensure(create_agent())

      updated = MemoryAgent.put_space(agent, :custom, Space.new_kv(), now: 999_999)

      assert MemoryAgent.get(updated).updated_at == 999_999
    end
  end

  describe "update_space/3" do
    test "updates space with function" do
      agent = MemoryAgent.ensure(create_agent())

      updated =
        MemoryAgent.update_space(agent, :world, fn space ->
          %{space | data: Map.put(space.data, :key, "value")}
        end)

      assert MemoryAgent.get_in_space(updated, :world, :key) == "value"
    end

    test "bumps both space and container rev" do
      agent = MemoryAgent.ensure(create_agent())

      updated =
        MemoryAgent.update_space(agent, :world, fn space ->
          %{space | data: Map.put(space.data, :key, "value")}
        end)

      memory = MemoryAgent.get(updated)
      assert memory.rev == 1
      assert memory.spaces.world.rev == 1
    end

    test "raises on missing space" do
      agent = MemoryAgent.ensure(create_agent())

      assert_raise ArgumentError, ~r/does not exist/, fn ->
        MemoryAgent.update_space(agent, :nonexistent, fn s -> s end)
      end
    end

    test "accepts injectable timestamp" do
      agent = MemoryAgent.ensure(create_agent())

      updated =
        MemoryAgent.update_space(
          agent,
          :world,
          fn space -> %{space | data: Map.put(space.data, :key, "val")} end,
          now: 123_456
        )

      assert MemoryAgent.get(updated).updated_at == 123_456
    end
  end

  describe "ensure_space/3" do
    test "creates space if missing" do
      agent = MemoryAgent.ensure(create_agent())

      updated = MemoryAgent.ensure_space(agent, :blackboard, %{})

      assert MemoryAgent.has_space?(updated, :blackboard)
      assert Space.map?(MemoryAgent.space(updated, :blackboard))
    end

    test "creates list space" do
      agent = MemoryAgent.ensure(create_agent())

      updated = MemoryAgent.ensure_space(agent, :evidence, [])

      assert MemoryAgent.has_space?(updated, :evidence)
      assert Space.list?(MemoryAgent.space(updated, :evidence))
    end

    test "does not overwrite existing space" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.put_in_space(:world, :key, "value")

      updated = MemoryAgent.ensure_space(agent, :world, %{})

      assert MemoryAgent.get_in_space(updated, :world, :key) == "value"
    end
  end

  describe "delete_space/2" do
    test "deletes custom space" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.ensure_space(:custom, %{})

      assert MemoryAgent.has_space?(agent, :custom)

      updated = MemoryAgent.delete_space(agent, :custom)
      refute MemoryAgent.has_space?(updated, :custom)
    end

    test "raises on reserved space :tasks" do
      agent = MemoryAgent.ensure(create_agent())

      assert_raise ArgumentError, ~r/cannot delete reserved/, fn ->
        MemoryAgent.delete_space(agent, :tasks)
      end
    end

    test "raises on reserved space :world" do
      agent = MemoryAgent.ensure(create_agent())

      assert_raise ArgumentError, ~r/cannot delete reserved/, fn ->
        MemoryAgent.delete_space(agent, :world)
      end
    end

    test "accepts injectable timestamp" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.ensure_space(:custom, %{})

      updated = MemoryAgent.delete_space(agent, :custom, now: 777_777)

      assert MemoryAgent.get(updated).updated_at == 777_777
    end
  end

  describe "spaces/1" do
    test "returns nil when no memory" do
      assert MemoryAgent.spaces(create_agent()) == nil
    end

    test "returns spaces map" do
      agent = MemoryAgent.ensure(create_agent())
      spaces = MemoryAgent.spaces(agent)
      assert is_map(spaces)
      assert Map.has_key?(spaces, :world)
      assert Map.has_key?(spaces, :tasks)
    end
  end

  describe "has_space?/2" do
    test "returns true for existing space" do
      agent = MemoryAgent.ensure(create_agent())
      assert MemoryAgent.has_space?(agent, :world) == true
    end

    test "returns false for non-existent space" do
      agent = MemoryAgent.ensure(create_agent())
      assert MemoryAgent.has_space?(agent, :nonexistent) == false
    end
  end

  describe "map space operations" do
    test "get_in_space returns value" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.put_in_space(:world, :temp, 22)

      assert MemoryAgent.get_in_space(agent, :world, :temp) == 22
    end

    test "get_in_space returns default when key missing" do
      agent = MemoryAgent.ensure(create_agent())
      assert MemoryAgent.get_in_space(agent, :world, :missing, :default) == :default
    end

    test "get_in_space raises on list space" do
      agent = MemoryAgent.ensure(create_agent())

      assert_raise ArgumentError, ~r/not a map space/, fn ->
        MemoryAgent.get_in_space(agent, :tasks, :key)
      end
    end

    test "put_in_space stores value" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.put_in_space(:world, :door, :open)

      assert MemoryAgent.get_in_space(agent, :world, :door) == :open
    end

    test "delete_from_space removes key" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.put_in_space(:world, :temp, 22)
        |> MemoryAgent.delete_from_space(:world, :temp)

      assert MemoryAgent.get_in_space(agent, :world, :temp) == nil
    end
  end

  describe "list space operations" do
    test "append_to_space adds to end" do
      agent =
        create_agent()
        |> MemoryAgent.ensure()
        |> MemoryAgent.append_to_space(:tasks, %{id: "t1", text: "first"})
        |> MemoryAgent.append_to_space(:tasks, %{id: "t2", text: "second"})

      space = MemoryAgent.space(agent, :tasks)
      assert length(space.data) == 2
      assert Enum.at(space.data, 0).id == "t1"
      assert Enum.at(space.data, 1).id == "t2"
    end

    test "append_to_space raises on map space" do
      agent = MemoryAgent.ensure(create_agent())

      assert_raise ArgumentError, ~r/not a list space/, fn ->
        MemoryAgent.append_to_space(agent, :world, "item")
      end
    end
  end

  describe "revision tracking" do
    test "container rev increments on any space mutation" do
      agent = MemoryAgent.ensure(create_agent())

      agent = MemoryAgent.put_in_space(agent, :world, :key1, "val1")
      assert MemoryAgent.get(agent).rev == 1

      agent = MemoryAgent.append_to_space(agent, :tasks, %{id: "t1", text: "A task"})
      assert MemoryAgent.get(agent).rev == 2
    end

    test "space rev increments independently" do
      agent = MemoryAgent.ensure(create_agent())

      agent = MemoryAgent.put_in_space(agent, :world, :key1, "val1")
      agent = MemoryAgent.put_in_space(agent, :world, :key2, "val2")

      memory = MemoryAgent.get(agent)
      assert memory.spaces.world.rev == 2
      assert memory.spaces.tasks.rev == 0
    end

    test "different spaces track revs independently" do
      agent = MemoryAgent.ensure(create_agent())

      agent = MemoryAgent.put_in_space(agent, :world, :key1, "val1")
      agent = MemoryAgent.append_to_space(agent, :tasks, %{id: "t1", text: "Task 1"})
      agent = MemoryAgent.put_in_space(agent, :world, :key2, "val2")

      memory = MemoryAgent.get(agent)
      assert memory.spaces.world.rev == 2
      assert memory.spaces.tasks.rev == 1
      assert memory.rev == 3
    end
  end
end
