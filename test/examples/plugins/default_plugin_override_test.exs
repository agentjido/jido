defmodule JidoExampleTest.DefaultPluginOverrideTest do
  @moduledoc """
  Example test demonstrating how to override, replace, or disable default plugins.

  This test shows:
  - Default plugins (like Jido.Thread.Plugin) are auto-included in all agents
  - Replacing a default plugin with a custom implementation via `default_plugins: %{}`
  - Passing config to a replacement plugin
  - Disabling a specific default plugin
  - Disabling all default plugins entirely

  Run with: mix test --include example
  """
  use JidoTest.Case, async: true

  @moduletag :example
  @moduletag timeout: 15_000

  # ===========================================================================
  # PLUGINS: Custom replacement for Jido.Thread.Plugin
  # ===========================================================================

  defmodule CustomThreadPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "custom_thread",
      state_key: :__thread__,
      actions: [],
      description: "Custom replacement for the default thread plugin."

    @impl Jido.Plugin
    def mount(_agent, config) do
      {:ok, %{custom_initialized: true, max_entries: Map.get(config, :max_entries, 500)}}
    end
  end

  # ===========================================================================
  # AGENTS: Various default_plugins configurations
  # ===========================================================================

  defmodule DefaultAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_agent",
      description: "Plain agent — gets Thread.Plugin automatically",
      schema: [
        status: [type: :atom, default: :idle]
      ]
  end

  defmodule OverriddenAgent do
    @moduledoc false
    use Jido.Agent,
      name: "overridden_agent",
      description: "Replaces Thread.Plugin with CustomThreadPlugin",
      schema: [
        status: [type: :atom, default: :idle]
      ],
      default_plugins: %{__thread__: CustomThreadPlugin}
  end

  defmodule ConfiguredAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_agent",
      description: "Replaces Thread.Plugin with CustomThreadPlugin + config",
      schema: [
        status: [type: :atom, default: :idle]
      ],
      default_plugins: %{__thread__: {CustomThreadPlugin, %{max_entries: 50}}}
  end

  defmodule DisabledAgent do
    @moduledoc false
    use Jido.Agent,
      name: "disabled_agent",
      description: "Disables only the __thread__ default plugin",
      schema: [
        status: [type: :atom, default: :idle]
      ],
      default_plugins: %{__thread__: false}
  end

  defmodule BareAgent do
    @moduledoc false
    use Jido.Agent,
      name: "bare_agent",
      description: "Disables all default plugins entirely",
      schema: [
        status: [type: :atom, default: :idle]
      ],
      default_plugins: false
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "default plugins are auto-included" do
    test "default agent includes Thread.Plugin and Identity.Plugin in plugin_specs" do
      specs = DefaultAgent.plugin_specs()
      modules = Enum.map(specs, & &1.module)

      assert Jido.Thread.Plugin in modules
      assert Jido.Identity.Plugin in modules
    end
  end

  describe "replacing a default plugin" do
    test "overridden agent uses CustomThreadPlugin instead of Thread.Plugin" do
      agent = OverriddenAgent.new()
      specs = OverriddenAgent.plugin_specs()

      assert hd(specs).module == CustomThreadPlugin
      assert agent.state.__thread__.custom_initialized == true
      assert agent.state.__thread__.max_entries == 500
    end

    test "configured agent receives config in mount/2" do
      agent = ConfiguredAgent.new()

      assert agent.state.__thread__.custom_initialized == true
      assert agent.state.__thread__.max_entries == 50
    end
  end

  describe "disabling default plugins" do
    test "disabled agent does not have :__thread__ in state" do
      agent = DisabledAgent.new()
      specs = DisabledAgent.plugin_specs()
      modules = Enum.map(specs, & &1.module)

      refute Jido.Thread.Plugin in modules
      refute Map.has_key?(agent.state, :__thread__)
    end

    test "bare agent with all defaults disabled does not have :__thread__" do
      agent = BareAgent.new()

      assert BareAgent.plugin_specs() == []
      refute Map.has_key?(agent.state, :__thread__)
    end
  end

  describe "agents with overridden defaults still work normally" do
    test "default and overridden agents both initialize via new()" do
      default = DefaultAgent.new(state: %{status: :running})
      overridden = OverriddenAgent.new(state: %{status: :running})

      assert default.state.status == :running
      assert overridden.state.status == :running

      assert overridden.state.__thread__.custom_initialized == true
    end
  end
end
