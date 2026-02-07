defmodule JidoTest.Plugin.RequirementsTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Instance
  alias Jido.Plugin.Requirements

  defmodule PluginNoRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "no_requires",
      state_key: :no_requires,
      actions: [JidoTest.PluginTestAction]
  end

  defmodule PluginWithConfigRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "config_requires",
      state_key: :config_requires,
      actions: [JidoTest.PluginTestAction],
      requires: [
        {:config, :token},
        {:config, :channel}
      ]
  end

  defmodule PluginWithAppRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "app_requires",
      state_key: :app_requires,
      actions: [JidoTest.PluginTestAction],
      requires: [
        {:app, :elixir}
      ]
  end

  defmodule PluginWithMissingAppRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "missing_app_requires",
      state_key: :missing_app_requires,
      actions: [JidoTest.PluginTestAction],
      requires: [
        {:app, :nonexistent_app_xyz}
      ]
  end

  defmodule PluginWithPluginRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_requires",
      state_key: :plugin_requires,
      actions: [JidoTest.PluginTestAction],
      requires: [
        {:plugin, "no_requires"}
      ]
  end

  defmodule PluginWithMixedRequires do
    @moduledoc false
    use Jido.Plugin,
      name: "mixed_requires",
      state_key: :mixed_requires,
      actions: [JidoTest.PluginTestAction],
      requires: [
        {:config, :api_key},
        {:app, :elixir},
        {:plugin, "no_requires"}
      ]
  end

  describe "validate_requirements/2" do
    test "returns :valid for plugin with no requirements" do
      instance = Instance.new(PluginNoRequires)
      context = %{mounted_plugins: [], resolved_config: %{}}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns :valid when config requirements are met" do
      instance = Instance.new(PluginWithConfigRequires)

      context = %{
        mounted_plugins: [],
        resolved_config: %{token: "abc", channel: "#general"}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns error when config requirements are missing" do
      instance = Instance.new(PluginWithConfigRequires)
      context = %{mounted_plugins: [], resolved_config: %{token: "abc"}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:config, :channel} in missing
    end

    test "returns error when config value is nil" do
      instance = Instance.new(PluginWithConfigRequires)
      context = %{mounted_plugins: [], resolved_config: %{token: "abc", channel: nil}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:config, :channel} in missing
    end

    test "returns :valid when app requirement is met" do
      instance = Instance.new(PluginWithAppRequires)
      context = %{mounted_plugins: [], resolved_config: %{}}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end

    test "returns error when app requirement is not met" do
      instance = Instance.new(PluginWithMissingAppRequires)
      context = %{mounted_plugins: [], resolved_config: %{}}

      assert {:error, missing} = Requirements.validate_requirements(instance, context)
      assert {:app, :nonexistent_app_xyz} in missing
    end

    test "returns :valid when plugin requirement is met" do
      no_requires_instance = Instance.new(PluginNoRequires)
      plugin_requires_instance = Instance.new(PluginWithPluginRequires)

      context = %{
        mounted_plugins: [no_requires_instance],
        resolved_config: %{}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(plugin_requires_instance, context)
    end

    test "returns error when plugin requirement is not met" do
      plugin_requires_instance = Instance.new(PluginWithPluginRequires)
      context = %{mounted_plugins: [], resolved_config: %{}}

      assert {:error, missing} =
               Requirements.validate_requirements(plugin_requires_instance, context)

      assert {:plugin, "no_requires"} in missing
    end

    test "returns :valid when all mixed requirements are met" do
      no_requires_instance = Instance.new(PluginNoRequires)
      mixed_instance = Instance.new(PluginWithMixedRequires)

      context = %{
        mounted_plugins: [no_requires_instance],
        resolved_config: %{api_key: "secret"}
      }

      assert {:ok, :valid} = Requirements.validate_requirements(mixed_instance, context)
    end

    test "returns all missing requirements for mixed plugin" do
      mixed_instance = Instance.new(PluginWithMixedRequires)
      context = %{mounted_plugins: [], resolved_config: %{}}

      assert {:error, missing} = Requirements.validate_requirements(mixed_instance, context)
      assert {:config, :api_key} in missing
      assert {:plugin, "no_requires"} in missing
      refute {:app, :elixir} in missing
    end

    test "uses instance config when resolved_config not in context" do
      instance = Instance.new({PluginWithConfigRequires, %{token: "abc", channel: "#test"}})
      context = %{mounted_plugins: []}

      assert {:ok, :valid} = Requirements.validate_requirements(instance, context)
    end
  end

  describe "validate_all_requirements/2" do
    test "returns :valid when all plugins have requirements met" do
      no_requires_instance = Instance.new(PluginNoRequires)
      app_requires_instance = Instance.new(PluginWithAppRequires)

      instances = [no_requires_instance, app_requires_instance]
      config_map = %{}

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end

    test "returns error map with all missing requirements" do
      config_requires_instance = Instance.new(PluginWithConfigRequires)
      missing_app_instance = Instance.new(PluginWithMissingAppRequires)

      instances = [config_requires_instance, missing_app_instance]
      config_map = %{}

      assert {:error, missing_by_plugin} =
               Requirements.validate_all_requirements(instances, config_map)

      assert Map.has_key?(missing_by_plugin, "config_requires")
      assert Map.has_key?(missing_by_plugin, "missing_app_requires")

      assert {:config, :token} in missing_by_plugin["config_requires"]
      assert {:config, :channel} in missing_by_plugin["config_requires"]
      assert {:app, :nonexistent_app_xyz} in missing_by_plugin["missing_app_requires"]
    end

    test "uses config_map for resolved config per plugin" do
      config_requires_instance = Instance.new(PluginWithConfigRequires)
      instances = [config_requires_instance]

      config_map = %{
        config_requires: %{token: "abc", channel: "#test"}
      }

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end

    test "plugin requirements check against all mounted plugins" do
      no_requires_instance = Instance.new(PluginNoRequires)
      plugin_requires_instance = Instance.new(PluginWithPluginRequires)

      instances = [no_requires_instance, plugin_requires_instance]
      config_map = %{}

      assert {:ok, :valid} = Requirements.validate_all_requirements(instances, config_map)
    end
  end

  describe "format_error/1" do
    test "formats single plugin with single requirement" do
      missing = %{"slack" => [{:config, :token}]}
      error = Requirements.format_error(missing)

      assert error =~ "Missing requirements for plugins:"
      assert error =~ "slack requires {:config, :token}"
    end

    test "formats single plugin with multiple requirements" do
      missing = %{"slack" => [{:config, :token}, {:app, :req}]}
      error = Requirements.format_error(missing)

      assert error =~ "slack requires {:config, :token}, {:app, :req}"
    end

    test "formats multiple plugins" do
      missing = %{
        "slack" => [{:config, :token}],
        "database" => [{:app, :ecto}]
      }

      error = Requirements.format_error(missing)

      assert error =~ "Missing requirements for plugins:"
      assert error =~ "slack requires"
      assert error =~ "database requires"
    end
  end
end
