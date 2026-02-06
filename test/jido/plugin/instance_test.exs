defmodule JidoTest.Plugin.InstanceTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Instance

  defmodule TestPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "test_plugin",
      state_key: :test,
      actions: [JidoTest.PluginTestAction],
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule SlackPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "slack",
      state_key: :slack,
      actions: [JidoTest.PluginTestAction],
      schema: Zoi.object(%{token: Zoi.string() |> Zoi.optional()})
  end

  defmodule SingletonPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "singleton_plugin",
      state_key: :singleton_state,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  describe "new/1" do
    test "creates instance from module alone" do
      instance = Instance.new(TestPlugin)

      assert instance.module == TestPlugin
      assert instance.as == nil
      assert instance.config == %{}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_plugin"
      assert instance.manifest.name == "test_plugin"
    end

    test "creates instance from {module, map} tuple" do
      instance = Instance.new({TestPlugin, %{custom: "value"}})

      assert instance.module == TestPlugin
      assert instance.as == nil
      assert instance.config == %{custom: "value"}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_plugin"
    end

    test "creates instance from {module, keyword_list} without :as" do
      instance = Instance.new({TestPlugin, [custom: "value", other: 123]})

      assert instance.module == TestPlugin
      assert instance.as == nil
      assert instance.config == %{custom: "value", other: 123}
      assert instance.state_key == :test
      assert instance.route_prefix == "test_plugin"
    end

    test "creates instance with :as option from keyword list" do
      instance = Instance.new({SlackPlugin, as: :support, token: "support-token"})

      assert instance.module == SlackPlugin
      assert instance.as == :support
      assert instance.config == %{token: "support-token"}
      assert instance.state_key == :slack_support
      assert instance.route_prefix == "support.slack"
    end

    test "creates instance with only :as option" do
      instance = Instance.new({SlackPlugin, as: :sales})

      assert instance.module == SlackPlugin
      assert instance.as == :sales
      assert instance.config == %{}
      assert instance.state_key == :slack_sales
      assert instance.route_prefix == "sales.slack"
    end

    test "manifest is populated from plugin module" do
      instance = Instance.new(TestPlugin)

      assert instance.manifest.module == TestPlugin
      assert instance.manifest.name == "test_plugin"
      assert instance.manifest.state_key == :test
    end
  end

  describe "derive_state_key/2" do
    test "returns base key when as is nil" do
      assert Instance.derive_state_key(:slack, nil) == :slack
      assert Instance.derive_state_key(:database, nil) == :database
    end

    test "appends alias to base key" do
      assert Instance.derive_state_key(:slack, :support) == :slack_support
      assert Instance.derive_state_key(:slack, :sales) == :slack_sales
      assert Instance.derive_state_key(:database, :primary) == :database_primary
    end
  end

  describe "derive_route_prefix/2" do
    test "returns base name when as is nil" do
      assert Instance.derive_route_prefix("slack", nil) == "slack"
      assert Instance.derive_route_prefix("database", nil) == "database"
    end

    test "prefixes with alias" do
      assert Instance.derive_route_prefix("slack", :support) == "support.slack"
      assert Instance.derive_route_prefix("slack", :sales) == "sales.slack"
      assert Instance.derive_route_prefix("database", :primary) == "primary.database"
    end
  end

  describe "multiple instances of same plugin" do
    test "same plugin with different :as values get different state keys" do
      support_instance = Instance.new({SlackPlugin, as: :support})
      sales_instance = Instance.new({SlackPlugin, as: :sales})
      default_instance = Instance.new(SlackPlugin)

      assert support_instance.state_key == :slack_support
      assert sales_instance.state_key == :slack_sales
      assert default_instance.state_key == :slack

      assert support_instance.state_key != sales_instance.state_key
      assert support_instance.state_key != default_instance.state_key
      assert sales_instance.state_key != default_instance.state_key
    end

    test "same plugin with different :as values get different route prefixes" do
      support_instance = Instance.new({SlackPlugin, as: :support})
      sales_instance = Instance.new({SlackPlugin, as: :sales})
      default_instance = Instance.new(SlackPlugin)

      assert support_instance.route_prefix == "support.slack"
      assert sales_instance.route_prefix == "sales.slack"
      assert default_instance.route_prefix == "slack"
    end

    test "different configs are preserved per instance" do
      support_instance = Instance.new({SlackPlugin, as: :support, token: "support-token"})
      sales_instance = Instance.new({SlackPlugin, as: :sales, token: "sales-token"})

      assert support_instance.config == %{token: "support-token"}
      assert sales_instance.config == %{token: "sales-token"}
    end
  end

  describe "singleton guardrail" do
    test "singleton plugin can be created without alias" do
      instance = Instance.new(SingletonPlugin)

      assert instance.module == SingletonPlugin
      assert instance.as == nil
      assert instance.state_key == :singleton_state
    end

    test "singleton plugin with config map works (no alias)" do
      instance = Instance.new({SingletonPlugin, %{custom: "value"}})

      assert instance.module == SingletonPlugin
      assert instance.as == nil
      assert instance.config == %{custom: "value"}
    end

    test "singleton plugin raises when aliased with as:" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        Instance.new({SingletonPlugin, as: :custom_alias})
      end
    end

    test "singleton plugin raises with as: and config" do
      assert_raise ArgumentError, ~r/Cannot alias singleton plugin/, fn ->
        Instance.new({SingletonPlugin, as: :custom_alias, token: "abc"})
      end
    end

    test "non-singleton plugin can still be aliased" do
      instance = Instance.new({SlackPlugin, as: :support})
      assert instance.as == :support
    end
  end
end
