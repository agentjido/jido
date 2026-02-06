defmodule JidoTest.Memory.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Memory
  alias Jido.Memory.Plugin, as: MemoryPlugin

  describe "plugin metadata" do
    test "name is memory" do
      assert MemoryPlugin.name() == "memory"
    end

    test "state_key is :__memory__" do
      assert MemoryPlugin.state_key() == :__memory__
    end

    test "is singleton" do
      assert MemoryPlugin.singleton?() == true
    end

    test "has memory capability" do
      assert :memory in MemoryPlugin.capabilities()
    end

    test "has no actions" do
      assert MemoryPlugin.actions() == []
    end

    test "schema is nil (no auto-initialization)" do
      assert MemoryPlugin.schema() == nil
    end
  end

  describe "mount/2" do
    test "returns {:ok, nil} (does not create memory)" do
      assert {:ok, nil} = MemoryPlugin.mount(nil, %{})
    end
  end

  describe "manifest" do
    test "singleton is true in manifest" do
      manifest = MemoryPlugin.manifest()
      assert manifest.singleton == true
    end

    test "state_key is :__memory__ in manifest" do
      manifest = MemoryPlugin.manifest()
      assert manifest.state_key == :__memory__
    end
  end

  describe "on_checkpoint/2" do
    test "keeps memory struct" do
      memory = Memory.new(id: "m-1")
      assert :keep = MemoryPlugin.on_checkpoint(memory, %{})
    end

    test "keeps nil state" do
      assert :keep = MemoryPlugin.on_checkpoint(nil, %{})
    end
  end

  describe "agent integration" do
    defmodule AgentWithMemory do
      use Jido.Agent, name: "memory_plugin_test_agent"
    end

    defmodule AgentWithoutMemory do
      use Jido.Agent,
        name: "memory_plugin_test_no_memory",
        default_plugins: %{__memory__: false}
    end

    test "agent includes memory plugin by default" do
      modules = AgentWithMemory.plugins()
      assert Jido.Memory.Plugin in modules
    end

    test "agent state does not contain :__memory__ key initially" do
      agent = AgentWithMemory.new()
      refute Map.has_key?(agent.state, :__memory__)
    end

    test "agent can disable memory plugin" do
      modules = AgentWithoutMemory.plugins()
      refute Jido.Memory.Plugin in modules
    end

    test "memory can be attached after creation via Memory.Agent" do
      agent = AgentWithMemory.new()
      agent = Memory.Agent.ensure(agent)
      assert %Memory{} = Memory.Agent.get(agent)
    end

    test "cannot alias memory plugin" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        Jido.Plugin.Instance.new({Jido.Memory.Plugin, as: :my_memory})
      end
    end
  end
end
