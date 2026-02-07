defmodule JidoTest.Agent.DefaultPluginsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.DefaultPlugins

  defmodule FakeMemoryPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "fake_memory",
      state_key: :__memory__,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  defmodule FakeThreadPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "fake_thread",
      state_key: :__thread__,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  defmodule ReplacementMemoryPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "replacement_memory",
      state_key: :__memory__,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  defmodule UserPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "user_plugin",
      state_key: :user_stuff,
      actions: [JidoTest.PluginTestAction]
  end

  describe "package_defaults/0" do
    test "returns list with Thread.Plugin, Identity.Plugin, and Memory.Plugin" do
      assert DefaultPlugins.package_defaults() == [
               Jido.Thread.Plugin,
               Jido.Identity.Plugin,
               Jido.Memory.Plugin
             ]
    end
  end

  describe "apply_agent_overrides/2" do
    test "nil overrides returns defaults unchanged" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      assert DefaultPlugins.apply_agent_overrides(defaults, nil) == defaults
    end

    test "false disables all defaults" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      assert DefaultPlugins.apply_agent_overrides(defaults, false) == []
    end

    test "empty map returns defaults unchanged" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      assert DefaultPlugins.apply_agent_overrides(defaults, %{}) == defaults
    end

    test "exclude a default by state_key" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      result = DefaultPlugins.apply_agent_overrides(defaults, %{__thread__: false})
      assert result == [FakeMemoryPlugin]
    end

    test "replace a default with another module" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]

      result =
        DefaultPlugins.apply_agent_overrides(defaults, %{__memory__: ReplacementMemoryPlugin})

      assert result == [ReplacementMemoryPlugin, FakeThreadPlugin]
    end

    test "replace a default with module and config tuple" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]

      result =
        DefaultPlugins.apply_agent_overrides(defaults, %{
          __memory__: {ReplacementMemoryPlugin, %{timeout: 5000}}
        })

      assert result == [{ReplacementMemoryPlugin, %{timeout: 5000}}, FakeThreadPlugin]
    end

    test "combine exclude and replace" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      overrides = %{__thread__: false, __memory__: ReplacementMemoryPlugin}
      result = DefaultPlugins.apply_agent_overrides(defaults, overrides)
      assert result == [ReplacementMemoryPlugin]
    end

    test "invalid override key raises CompileError" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]

      assert_raise CompileError, ~r/Invalid default_plugins override keys/, fn ->
        DefaultPlugins.apply_agent_overrides(defaults, %{nonexistent: false})
      end
    end

    test "handles defaults with config tuples" do
      defaults = [{FakeMemoryPlugin, %{opt: true}}, FakeThreadPlugin]
      result = DefaultPlugins.apply_agent_overrides(defaults, %{__thread__: false})
      assert result == [{FakeMemoryPlugin, %{opt: true}}]
    end

    test "replace a default that has config tuple" do
      defaults = [{FakeMemoryPlugin, %{opt: true}}, FakeThreadPlugin]

      result =
        DefaultPlugins.apply_agent_overrides(defaults, %{__memory__: ReplacementMemoryPlugin})

      assert result == [ReplacementMemoryPlugin, FakeThreadPlugin]
    end

    test "exclude all defaults individually" do
      defaults = [FakeMemoryPlugin, FakeThreadPlugin]
      overrides = %{__memory__: false, __thread__: false}
      result = DefaultPlugins.apply_agent_overrides(defaults, overrides)
      assert result == []
    end

    test "single default list" do
      defaults = [FakeMemoryPlugin]
      result = DefaultPlugins.apply_agent_overrides(defaults, %{__memory__: false})
      assert result == []
    end
  end

  describe "agent macro integration" do
    test "agent with no default_plugins option gets framework defaults" do
      defmodule AgentNoDefaults do
        use Jido.Agent, name: "dp_agent_no_defaults"
      end

      instances = AgentNoDefaults.plugin_instances()
      assert length(instances) == 3
      modules = Enum.map(instances, & &1.module)
      assert Jido.Thread.Plugin in modules
      assert Jido.Identity.Plugin in modules
      assert Jido.Memory.Plugin in modules
    end

    test "agent with default_plugins: false gets no defaults" do
      defmodule AgentDisableDefaults do
        use Jido.Agent,
          name: "dp_agent_disable_defaults",
          default_plugins: false
      end

      assert AgentDisableDefaults.plugin_instances() == []
    end

    test "agent with plugins still gets them when default_plugins is false" do
      defmodule AgentUserPluginsOnly do
        use Jido.Agent,
          name: "dp_agent_user_only",
          default_plugins: false,
          plugins: [UserPlugin]
      end

      instances = AgentUserPluginsOnly.plugin_instances()
      assert length(instances) == 1
      assert hd(instances).module == UserPlugin
    end

    test "agent with jido: option resolves defaults from instance" do
      defmodule FakeJido do
        def __default_plugins__, do: [FakeMemoryPlugin]
      end

      defmodule AgentWithJido do
        use Jido.Agent,
          name: "dp_agent_with_jido",
          jido: FakeJido
      end

      instances = AgentWithJido.plugin_instances()
      assert length(instances) == 1
      assert hd(instances).module == FakeMemoryPlugin
    end

    test "agent with jido: and default_plugins override map" do
      defmodule FakeJido2 do
        def __default_plugins__, do: [FakeMemoryPlugin, FakeThreadPlugin]
      end

      defmodule AgentWithJidoOverride do
        use Jido.Agent,
          name: "dp_agent_jido_override",
          jido: FakeJido2,
          default_plugins: %{__thread__: false}
      end

      instances = AgentWithJidoOverride.plugin_instances()
      assert length(instances) == 1
      assert hd(instances).module == FakeMemoryPlugin
    end

    test "agent with jido: and replacement in default_plugins" do
      defmodule FakeJido3 do
        def __default_plugins__, do: [FakeMemoryPlugin, FakeThreadPlugin]
      end

      defmodule AgentWithReplacement do
        use Jido.Agent,
          name: "dp_agent_replacement",
          jido: FakeJido3,
          default_plugins: %{__memory__: ReplacementMemoryPlugin}
      end

      instances = AgentWithReplacement.plugin_instances()
      modules = Enum.map(instances, & &1.module)
      assert ReplacementMemoryPlugin in modules
      assert FakeThreadPlugin in modules
      refute FakeMemoryPlugin in modules
    end

    test "defaults mount before user plugins" do
      defmodule FakeJido4 do
        def __default_plugins__, do: [FakeMemoryPlugin]
      end

      defmodule AgentMountOrder do
        use Jido.Agent,
          name: "dp_agent_mount_order",
          jido: FakeJido4,
          plugins: [UserPlugin]
      end

      instances = AgentMountOrder.plugin_instances()
      assert length(instances) == 2
      assert Enum.at(instances, 0).module == FakeMemoryPlugin
      assert Enum.at(instances, 1).module == UserPlugin
    end
  end
end
