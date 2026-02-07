defmodule JidoTest.PluginMountTest do
  use ExUnit.Case, async: true

  # Test action for plugins
  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "test_action",
      schema: []

    def run(_params, _context), do: {:ok, %{}}
  end

  # Plugin with custom mount that adds state
  defmodule MountingPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "mounting_plugin",
      state_key: :mounting,
      actions: [JidoTest.PluginMountTest.TestAction],
      schema: Zoi.object(%{default_value: Zoi.integer() |> Zoi.default(0)})

    @impl Jido.Plugin
    def mount(_agent, config) do
      {:ok, %{mounted: true, initialized_at: DateTime.utc_now(), config_value: config[:setting]}}
    end
  end

  # Plugin with default mount (no override)
  defmodule DefaultMountPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "default_mount_plugin",
      state_key: :default_mount,
      actions: [JidoTest.PluginMountTest.TestAction],
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(42)})
  end

  # Plugin that reads from previously mounted plugin state
  defmodule DependentPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "dependent_plugin",
      state_key: :dependent,
      actions: [JidoTest.PluginMountTest.TestAction]

    @impl Jido.Plugin
    def mount(agent, _config) do
      # Read from :mounting plugin state if available
      mounting_state = Map.get(agent.state, :mounting, %{})
      was_mounted = Map.get(mounting_state, :mounted, false)
      {:ok, %{saw_mounting: was_mounted}}
    end
  end

  # Plugin that returns error from mount
  defmodule ErrorMountPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "error_mount_plugin",
      state_key: :error_mount,
      actions: [JidoTest.PluginMountTest.TestAction]

    @impl Jido.Plugin
    def mount(_agent, _config) do
      {:error, :mount_failed_intentionally}
    end
  end

  # Agent with mounting plugin
  defmodule MountingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "mounting_agent",
      plugins: [JidoTest.PluginMountTest.MountingPlugin]
  end

  # Agent with configured mounting plugin
  defmodule ConfiguredMountingAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_mounting_agent",
      plugins: [{JidoTest.PluginMountTest.MountingPlugin, %{setting: "custom_value"}}]
  end

  # Agent with default mount plugin
  defmodule DefaultMountAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_mount_agent",
      plugins: [JidoTest.PluginMountTest.DefaultMountPlugin]
  end

  # Agent with two plugins where second depends on first
  defmodule DependentPluginsAgent do
    @moduledoc false
    use Jido.Agent,
      name: "dependent_plugins_agent",
      plugins: [
        JidoTest.PluginMountTest.MountingPlugin,
        JidoTest.PluginMountTest.DependentPlugin
      ]
  end

  # Agent with error mounting plugin
  defmodule ErrorMountAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_mount_agent",
      plugins: [JidoTest.PluginMountTest.ErrorMountPlugin]
  end

  describe "mount/2 in Agent.new/1" do
    test "plugin with custom mount populates its state slice" do
      agent = MountingAgent.new()

      assert agent.state[:mounting][:mounted] == true
      assert agent.state[:mounting][:initialized_at] != nil
      # from schema
      assert agent.state[:mounting][:default_value] == 0
    end

    test "plugin mount receives config and can use it" do
      agent = ConfiguredMountingAgent.new()

      assert agent.state[:mounting][:config_value] == "custom_value"
    end

    test "plugin with default mount/2 still gets schema defaults" do
      agent = DefaultMountAgent.new()

      assert agent.state[:default_mount][:counter] == 42
      # Default mount returns empty map, so no additional fields
    end

    test "plugin mount can see previously mounted plugin state" do
      agent = DependentPluginsAgent.new()

      # First plugin should be mounted
      assert agent.state[:mounting][:mounted] == true

      # Second plugin should have seen the first plugin's state
      assert agent.state[:dependent][:saw_mounting] == true
    end

    test "plugin mount error raises with clear message" do
      assert_raise Jido.Error.InternalError, ~r/Plugin mount failed/, fn ->
        ErrorMountAgent.new()
      end
    end

    test "mount state merges with schema defaults, not replaces" do
      agent = MountingAgent.new()

      # Schema default should be preserved
      assert agent.state[:mounting][:default_value] == 0
      # Mount additions should be present
      assert agent.state[:mounting][:mounted] == true
    end

    test "custom initial state overrides both schema and mount" do
      agent = MountingAgent.new(state: %{mounting: %{default_value: 999, custom: :field}})

      # Custom value should override schema default
      assert agent.state[:mounting][:default_value] == 999
      # Mount values should still merge in
      assert agent.state[:mounting][:mounted] == true
      # Custom field preserved
      assert agent.state[:mounting][:custom] == :field
    end
  end
end
