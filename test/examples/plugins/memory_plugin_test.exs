defmodule JidoExampleTest.MemoryPluginTest do
  @moduledoc """
  Example test demonstrating Memory as a default plugin.

  This test shows:
  - Every agent gets `Jido.Memory.Plugin` automatically (default singleton plugin)
  - Using `Jido.Memory.Agent` helpers: `ensure/2`, `has_memory?/1`, `get/1`, `put/2`,
    `put_in_space/4`, `get_in_space/4`, `append_to_space/3`, `ensure_space/3`,
    `space/2`, `spaces/1`, `has_space?/2`, `delete_space/2`, `update_space/4`
  - Actions that manipulate memory spaces via cmd/2
  - Disabling the memory plugin with `default_plugins: %{__memory__: false}`

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.Memory
  alias Jido.Memory.Agent, as: MemAgent
  alias Jido.Memory.Space

  # ===========================================================================
  # ACTIONS
  # ===========================================================================

  defmodule UpdateWorldAction do
    @moduledoc false
    use Jido.Action,
      name: "update_world",
      schema: [
        key: [type: :atom, required: true],
        value: [type: :any, required: true]
      ]

    def run(%{key: key, value: value}, context) do
      alias Jido.Memory
      alias Jido.Memory.Space

      memory = Map.get(context.state, :__memory__) || Memory.new()
      world = Map.get(memory.spaces, :world, Space.new_kv())
      updated_world = %{world | data: Map.put(world.data, key, value), rev: world.rev + 1}

      updated_memory = %{
        memory
        | spaces: Map.put(memory.spaces, :world, updated_world),
          rev: memory.rev + 1
      }

      {:ok, %{__memory__: updated_memory}}
    end
  end

  # ===========================================================================
  # AGENTS
  # ===========================================================================

  defmodule MemoryAgent do
    @moduledoc false
    use Jido.Agent,
      name: "memory_agent",
      description: "Agent with default memory plugin",
      schema: [
        status: [type: :atom, default: :idle]
      ]
  end

  defmodule NoMemoryAgent do
    @moduledoc false
    use Jido.Agent,
      name: "no_memory_agent",
      description: "Agent with memory plugin disabled",
      default_plugins: %{__memory__: false},
      schema: [
        value: [type: :integer, default: 0]
      ]
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "memory plugin is a default singleton" do
    test "new agent has no memory until initialized on demand" do
      agent = MemoryAgent.new()

      refute MemAgent.has_memory?(agent)
    end

    test "MemAgent.ensure initializes memory on demand" do
      agent = MemoryAgent.new()

      agent = MemAgent.ensure(agent)

      assert MemAgent.has_memory?(agent)
      memory = MemAgent.get(agent)
      assert %Memory{} = memory
      assert Map.has_key?(memory.spaces, :world)
      assert Map.has_key?(memory.spaces, :tasks)
    end
  end

  describe "space operations" do
    test "put and get in map space (:world)" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      agent = MemAgent.put_in_space(agent, :world, :temperature, 22)
      assert MemAgent.get_in_space(agent, :world, :temperature) == 22

      agent = MemAgent.put_in_space(agent, :world, :humidity, 65)
      assert MemAgent.get_in_space(agent, :world, :humidity) == 65
      assert MemAgent.get_in_space(agent, :world, :temperature) == 22
    end

    test "append to list space (:tasks)" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      agent = MemAgent.append_to_space(agent, :tasks, %{id: "t1", text: "Check sensor"})
      agent = MemAgent.append_to_space(agent, :tasks, %{id: "t2", text: "Report status"})

      tasks_space = MemAgent.space(agent, :tasks)
      assert Space.list?(tasks_space)
      assert length(tasks_space.data) == 2
      assert Enum.map(tasks_space.data, & &1.id) == ["t1", "t2"]
    end

    test "ensure_space creates a new custom space" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      refute MemAgent.has_space?(agent, :custom)

      agent = MemAgent.ensure_space(agent, :custom, %{})
      assert MemAgent.has_space?(agent, :custom)

      custom_space = MemAgent.space(agent, :custom)
      assert Space.map?(custom_space)
    end

    test "delete_space works for custom spaces" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()
        |> MemAgent.ensure_space(:scratch, %{})

      assert MemAgent.has_space?(agent, :scratch)

      agent = MemAgent.delete_space(agent, :scratch)
      refute MemAgent.has_space?(agent, :scratch)
    end

    test "delete_space raises on reserved spaces" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      assert_raise ArgumentError, ~r/cannot delete reserved space/, fn ->
        MemAgent.delete_space(agent, :world)
      end
    end
  end

  describe "memory state via cmd/2" do
    test "cmd/2 with action preserves memory changes" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      {agent, []} = MemoryAgent.cmd(agent, {UpdateWorldAction, %{key: :location, value: "lab"}})

      assert MemAgent.has_memory?(agent)
      assert MemAgent.get_in_space(agent, :world, :location) == "lab"
    end

    test "multiple cmd/2 calls accumulate memory" do
      agent =
        MemoryAgent.new()
        |> MemAgent.ensure()

      {agent, []} = MemoryAgent.cmd(agent, {UpdateWorldAction, %{key: :x, value: 1}})
      {agent, []} = MemoryAgent.cmd(agent, {UpdateWorldAction, %{key: :y, value: 2}})

      assert MemAgent.get_in_space(agent, :world, :x) == 1
      assert MemAgent.get_in_space(agent, :world, :y) == 2
    end
  end

  describe "disabling memory plugin" do
    test "agent with __memory__ disabled has no memory capability" do
      agent = NoMemoryAgent.new()

      refute MemAgent.has_memory?(agent)
      refute Map.has_key?(agent.state, :__memory__)

      specs = NoMemoryAgent.plugin_specs()
      modules = Enum.map(specs, & &1.module)
      refute Jido.Memory.Plugin in modules
    end
  end
end
