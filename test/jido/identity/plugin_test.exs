defmodule JidoTest.Identity.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Identity
  alias Jido.Identity.Plugin, as: IdentityPlugin
  alias Jido.Plugin.Instance, as: PluginInstance

  describe "plugin metadata" do
    test "name is identity" do
      assert IdentityPlugin.name() == "identity"
    end

    test "state_key is :__identity__" do
      assert IdentityPlugin.state_key() == :__identity__
    end

    test "is singleton" do
      assert IdentityPlugin.singleton?() == true
    end

    test "has identity capability" do
      assert :identity in IdentityPlugin.capabilities()
    end

    test "has no actions" do
      assert IdentityPlugin.actions() == []
    end

    test "schema is nil (no auto-initialization)" do
      assert IdentityPlugin.schema() == nil
    end
  end

  describe "mount/2" do
    test "returns {:ok, nil} (does not create an identity)" do
      assert {:ok, nil} = IdentityPlugin.mount(nil, %{})
    end
  end

  describe "manifest" do
    test "singleton is true in manifest" do
      manifest = IdentityPlugin.manifest()
      assert manifest.singleton == true
    end

    test "state_key is :__identity__ in manifest" do
      manifest = IdentityPlugin.manifest()
      assert manifest.state_key == :__identity__
    end
  end

  describe "agent integration" do
    defmodule AgentWithIdentity do
      use Jido.Agent, name: "identity_plugin_test_agent"
    end

    defmodule AgentWithoutIdentity do
      use Jido.Agent,
        name: "identity_plugin_test_no_identity",
        default_plugins: %{__identity__: false}
    end

    test "agent includes identity plugin by default" do
      modules = AgentWithIdentity.plugins()
      assert Jido.Identity.Plugin in modules
    end

    test "agent state does not contain :__identity__ key initially" do
      agent = AgentWithIdentity.new()
      refute Map.has_key?(agent.state, :__identity__)
    end

    test "agent can disable identity plugin" do
      modules = AgentWithoutIdentity.plugins()
      refute Jido.Identity.Plugin in modules
    end

    test "identity can be attached after creation via Identity.Agent" do
      agent = AgentWithIdentity.new()
      agent = Identity.Agent.ensure(agent)
      assert %Identity{} = Identity.Agent.get(agent)
    end

    test "cannot alias identity plugin" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        PluginInstance.new({Jido.Identity.Plugin, as: :my_identity})
      end
    end
  end
end
