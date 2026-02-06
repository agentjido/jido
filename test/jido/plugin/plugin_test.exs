defmodule JidoTest.PluginTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Manifest
  alias Jido.Plugin.Spec

  # Plugin fixtures - these reference action modules from test/support/test_actions.ex
  # which are compiled before test files

  defmodule BasicPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "basic_plugin",
      state_key: :basic,
      actions: [JidoTest.PluginTestAction]
  end

  defmodule FullPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "full_plugin",
      state_key: :full,
      actions: [JidoTest.PluginTestAction, JidoTest.PluginTestAnotherAction],
      description: "A fully configured plugin",
      category: "test",
      vsn: "1.0.0",
      schema: Zoi.object(%{counter: Zoi.integer() |> Zoi.default(0)}),
      config_schema: Zoi.object(%{enabled: Zoi.boolean() |> Zoi.default(true)}),
      signal_patterns: ["plugin.**", "test.*"],
      tags: ["test", "full"],
      capabilities: [:messaging, :notifications],
      requires: [{:config, :api_key}, {:app, :req}],
      signal_routes: [
        {"post", JidoTest.PluginTestAction},
        {"get", JidoTest.PluginTestAnotherAction}
      ],
      schedules: [{"*/5 * * * *", JidoTest.PluginTestAction}]
  end

  defmodule CustomCallbackPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "custom_callback_plugin",
      state_key: :custom,
      actions: [JidoTest.PluginTestAction]

    @impl Jido.Plugin
    def mount(_agent, config) do
      {:ok, %{mounted: true, config: config}}
    end

    @impl Jido.Plugin
    def signal_routes(_config), do: [:custom_router]

    @impl Jido.Plugin
    def handle_signal(signal, context) do
      {:ok, %{signal: signal, context: context, handled: true}}
    end

    @impl Jido.Plugin
    def transform_result(action, result, _context) do
      {:ok, %{action: action, result: result, transformed: true}}
    end

    @impl Jido.Plugin
    def child_spec(config) do
      %{id: __MODULE__, start: {Agent, :start_link, [fn -> config end]}}
    end
  end

  defmodule MountErrorPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "mount_error_plugin",
      state_key: :mount_error,
      actions: [JidoTest.PluginTestAction]

    @impl Jido.Plugin
    def mount(_agent, _config) do
      {:error, :mount_failed}
    end
  end

  defmodule SingletonPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "singleton_plugin",
      state_key: :singleton_state,
      actions: [JidoTest.PluginTestAction],
      singleton: true
  end

  describe "plugin definition with required fields" do
    test "defines a basic plugin with required fields" do
      assert BasicPlugin.name() == "basic_plugin"
      assert BasicPlugin.state_key() == :basic
      assert BasicPlugin.actions() == [JidoTest.PluginTestAction]
    end

    test "optional fields default to nil or empty" do
      assert BasicPlugin.description() == nil
      assert BasicPlugin.category() == nil
      assert BasicPlugin.vsn() == nil
      assert BasicPlugin.schema() == nil
      assert BasicPlugin.config_schema() == nil
      assert BasicPlugin.signal_patterns() == []
      assert BasicPlugin.tags() == []
      assert BasicPlugin.capabilities() == []
      assert BasicPlugin.requires() == []
      assert BasicPlugin.signal_routes() == []
      assert BasicPlugin.schedules() == []
    end
  end

  describe "plugin definition with all optional fields" do
    test "defines a plugin with all optional fields" do
      assert FullPlugin.name() == "full_plugin"
      assert FullPlugin.state_key() == :full
      assert FullPlugin.actions() == [JidoTest.PluginTestAction, JidoTest.PluginTestAnotherAction]
      assert FullPlugin.description() == "A fully configured plugin"
      assert FullPlugin.category() == "test"
      assert FullPlugin.vsn() == "1.0.0"
      assert FullPlugin.schema() != nil
      assert FullPlugin.config_schema() != nil
      assert FullPlugin.signal_patterns() == ["plugin.**", "test.*"]
      assert FullPlugin.tags() == ["test", "full"]
      assert FullPlugin.capabilities() == [:messaging, :notifications]
      assert FullPlugin.requires() == [{:config, :api_key}, {:app, :req}]

      assert FullPlugin.signal_routes() == [
               {"post", JidoTest.PluginTestAction},
               {"get", JidoTest.PluginTestAnotherAction}
             ]

      assert FullPlugin.schedules() == [{"*/5 * * * *", JidoTest.PluginTestAction}]
    end
  end

  describe "plugin_spec/0 and plugin_spec/1" do
    test "plugin_spec/0 returns correct Spec struct with defaults" do
      spec = BasicPlugin.plugin_spec()

      assert %Spec{} = spec
      assert spec.module == BasicPlugin
      assert spec.name == "basic_plugin"
      assert spec.state_key == :basic
      assert spec.actions == [JidoTest.PluginTestAction]
      assert spec.config == %{}
      assert spec.description == nil
      assert spec.category == nil
      assert spec.vsn == nil
      assert spec.schema == nil
      assert spec.config_schema == nil
      assert spec.signal_patterns == []
      assert spec.tags == []
    end

    test "plugin_spec/0 returns correct Spec struct with all fields" do
      spec = FullPlugin.plugin_spec()

      assert %Spec{} = spec
      assert spec.module == FullPlugin
      assert spec.name == "full_plugin"
      assert spec.state_key == :full
      assert spec.actions == [JidoTest.PluginTestAction, JidoTest.PluginTestAnotherAction]
      assert spec.description == "A fully configured plugin"
      assert spec.category == "test"
      assert spec.vsn == "1.0.0"
      assert spec.schema != nil
      assert spec.config_schema != nil
      assert spec.signal_patterns == ["plugin.**", "test.*"]
      assert spec.tags == ["test", "full"]
    end

    test "plugin_spec/1 accepts config overrides" do
      spec = BasicPlugin.plugin_spec(%{custom_option: true, setting: "value"})

      assert spec.config == %{custom_option: true, setting: "value"}
    end

    test "plugin_spec/1 with empty config returns empty map" do
      spec = BasicPlugin.plugin_spec(%{})
      assert spec.config == %{}
    end
  end

  describe "metadata accessors" do
    @metadata_cases [
      # {function, BasicPlugin expected, FullPlugin expected}
      {:name, "basic_plugin", "full_plugin"},
      {:state_key, :basic, :full},
      {:description, nil, "A fully configured plugin"},
      {:category, nil, "test"},
      {:vsn, nil, "1.0.0"},
      {:signal_patterns, [], ["plugin.**", "test.*"]},
      {:tags, [], ["test", "full"]},
      {:actions, [JidoTest.PluginTestAction],
       [JidoTest.PluginTestAction, JidoTest.PluginTestAnotherAction]}
    ]

    for {fun, basic_expected, full_expected} <- @metadata_cases do
      @fun fun
      @basic_expected basic_expected
      @full_expected full_expected

      test "#{@fun}/0 returns correct value for BasicPlugin and FullPlugin" do
        assert apply(BasicPlugin, @fun, []) == @basic_expected
        assert apply(FullPlugin, @fun, []) == @full_expected
      end
    end

    test "schema/0 returns nil for BasicPlugin and Zoi schema for FullPlugin" do
      assert BasicPlugin.schema() == nil
      assert FullPlugin.schema() != nil
    end

    test "config_schema/0 returns nil for BasicPlugin and Zoi schema for FullPlugin" do
      assert BasicPlugin.config_schema() == nil
      assert FullPlugin.config_schema() != nil
    end
  end

  describe "compile-time validation" do
    test "missing required field raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingNamePlugin do
          use Jido.Plugin,
            state_key: :missing,
            actions: [JidoTest.PluginTestAction]
        end
      end
    end

    test "missing state_key raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingStateKeyPlugin do
          use Jido.Plugin,
            name: "missing_state_key",
            actions: [JidoTest.PluginTestAction]
        end
      end
    end

    test "missing actions raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule MissingActionsPlugin do
          use Jido.Plugin,
            name: "missing_actions",
            state_key: :missing
        end
      end
    end

    test "invalid action module raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule InvalidActionPlugin do
          use Jido.Plugin,
            name: "invalid_action",
            state_key: :invalid,
            actions: [NonExistentModule]
        end
      end
    end

    test "module that doesn't implement Action behavior raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule NotActionPlugin do
          use Jido.Plugin,
            name: "not_action",
            state_key: :not_action,
            actions: [JidoTest.NotAnActionModule]
        end
      end
    end

    test "invalid name format raises CompileError" do
      assert_raise CompileError, fn ->
        defmodule InvalidNamePlugin do
          use Jido.Plugin,
            name: "invalid-name-with-dashes",
            state_key: :invalid,
            actions: [JidoTest.PluginTestAction]
        end
      end
    end
  end

  describe "default callback implementations" do
    test "default mount/2 returns {:ok, empty map}" do
      result = BasicPlugin.mount(%{}, %{})
      assert result == {:ok, %{}}
    end

    test "default mount/2 ignores agent and config" do
      result = BasicPlugin.mount(:any_agent, %{any: :config})
      assert result == {:ok, %{}}
    end

    test "default signal_routes/1 returns empty list" do
      result = BasicPlugin.signal_routes(%{})
      assert result == []
    end

    test "default handle_signal/2 returns {:ok, nil}" do
      result = BasicPlugin.handle_signal(:some_signal, %{})
      assert result == {:ok, nil}
    end

    test "default transform_result/3 returns result unchanged" do
      result = BasicPlugin.transform_result(JidoTest.PluginTestAction, %{value: 42}, %{})
      assert result == %{value: 42}
    end

    test "default child_spec/1 returns nil" do
      result = BasicPlugin.child_spec(%{})
      assert result == nil
    end
  end

  describe "custom callback implementations" do
    test "custom mount/2 is called with agent and config" do
      agent = %{id: "test-agent"}
      config = %{setting: "value"}

      result = CustomCallbackPlugin.mount(agent, config)

      assert result == {:ok, %{mounted: true, config: config}}
    end

    test "mount/2 can return error" do
      result = MountErrorPlugin.mount(%{}, %{})
      assert result == {:error, :mount_failed}
    end

    test "custom signal_routes/1 returns custom routes" do
      result = CustomCallbackPlugin.signal_routes(%{some: :config})
      assert result == [:custom_router]
    end

    test "custom handle_signal/2 receives signal and context" do
      signal = %{type: "test.signal", data: %{}}
      context = %{agent_id: "test"}

      {:ok, result} = CustomCallbackPlugin.handle_signal(signal, context)

      assert result.signal == signal
      assert result.context == context
      assert result.handled == true
    end

    test "custom transform_result/3 transforms result" do
      action = JidoTest.PluginTestAction
      result = %{original: "result"}
      context = %{agent_id: "test"}

      {:ok, transformed} = CustomCallbackPlugin.transform_result(action, result, context)

      assert transformed.action == action
      assert transformed.result == result
      assert transformed.transformed == true
    end

    test "custom child_spec/1 returns supervisor child spec" do
      config = %{initial: "state"}

      spec = CustomCallbackPlugin.child_spec(config)

      assert spec.id == CustomCallbackPlugin
      assert {Agent, :start_link, [_fun]} = spec.start
    end
  end

  describe "Plugin.config_schema/0" do
    test "returns the Zoi schema for plugin configuration" do
      schema = Jido.Plugin.config_schema()
      assert is_struct(schema)
    end
  end

  describe "manifest/0" do
    test "returns correct Manifest struct for BasicPlugin" do
      manifest = BasicPlugin.manifest()

      assert %Manifest{} = manifest
      assert manifest.module == BasicPlugin
      assert manifest.name == "basic_plugin"
      assert manifest.state_key == :basic
      assert manifest.actions == [JidoTest.PluginTestAction]
      assert manifest.description == nil
      assert manifest.category == nil
      assert manifest.vsn == nil
      assert manifest.schema == nil
      assert manifest.config_schema == nil
      assert manifest.signal_patterns == []
      assert manifest.tags == []
      assert manifest.capabilities == []
      assert manifest.requires == []
      assert manifest.signal_routes == []
      assert manifest.schedules == []
    end

    test "returns correct Manifest struct for FullPlugin" do
      manifest = FullPlugin.manifest()

      assert %Manifest{} = manifest
      assert manifest.module == FullPlugin
      assert manifest.name == "full_plugin"
      assert manifest.state_key == :full
      assert manifest.actions == [JidoTest.PluginTestAction, JidoTest.PluginTestAnotherAction]
      assert manifest.description == "A fully configured plugin"
      assert manifest.category == "test"
      assert manifest.vsn == "1.0.0"
      assert manifest.schema != nil
      assert manifest.config_schema != nil
      assert manifest.signal_patterns == ["plugin.**", "test.*"]
      assert manifest.tags == ["test", "full"]
      assert manifest.capabilities == [:messaging, :notifications]
      assert manifest.requires == [{:config, :api_key}, {:app, :req}]

      assert manifest.signal_routes == [
               {"post", JidoTest.PluginTestAction},
               {"get", JidoTest.PluginTestAnotherAction}
             ]

      assert manifest.schedules == [{"*/5 * * * *", JidoTest.PluginTestAction}]
    end
  end

  describe "__plugin_metadata__/0" do
    test "returns correct metadata map for BasicPlugin" do
      metadata = BasicPlugin.__plugin_metadata__()

      assert metadata == %{
               name: "basic_plugin",
               description: nil,
               category: nil,
               tags: []
             }
    end

    test "returns correct metadata map for FullPlugin" do
      metadata = FullPlugin.__plugin_metadata__()

      assert metadata == %{
               name: "full_plugin",
               description: "A fully configured plugin",
               category: "test",
               tags: ["test", "full"]
             }
    end

    test "metadata is compatible with Jido.Discovery expectations" do
      metadata = FullPlugin.__plugin_metadata__()

      assert is_binary(metadata.name)
      assert is_binary(metadata.description) or is_nil(metadata.description)
      assert is_binary(metadata.category) or is_nil(metadata.category)
      assert is_list(metadata.tags)
    end
  end

  describe "new accessor functions" do
    test "capabilities/0 returns correct values" do
      assert BasicPlugin.capabilities() == []
      assert FullPlugin.capabilities() == [:messaging, :notifications]
    end

    test "requires/0 returns correct values" do
      assert BasicPlugin.requires() == []
      assert FullPlugin.requires() == [{:config, :api_key}, {:app, :req}]
    end

    test "signal_routes/0 returns correct values" do
      assert BasicPlugin.signal_routes() == []

      assert FullPlugin.signal_routes() == [
               {"post", JidoTest.PluginTestAction},
               {"get", JidoTest.PluginTestAnotherAction}
             ]
    end

    test "schedules/0 returns correct values" do
      assert BasicPlugin.schedules() == []
      assert FullPlugin.schedules() == [{"*/5 * * * *", JidoTest.PluginTestAction}]
    end
  end

  describe "backward compatibility" do
    test "existing plugins without new options still work" do
      assert BasicPlugin.name() == "basic_plugin"
      assert BasicPlugin.state_key() == :basic
      assert BasicPlugin.actions() == [JidoTest.PluginTestAction]
      assert BasicPlugin.signal_patterns() == []
      assert BasicPlugin.signal_routes(%{}) == []
    end

    test "plugin_spec still works correctly" do
      spec = FullPlugin.plugin_spec(%{custom: true})

      assert %Spec{} = spec
      assert spec.module == FullPlugin
      assert spec.config == %{custom: true}
    end
  end

  defmodule ExternalizePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "externalize_plugin",
      state_key: :ext,
      actions: []

    @impl Jido.Plugin
    def on_checkpoint(%{id: id, rev: rev}, _ctx) do
      {:externalize, :ext_pointer, %{id: id, rev: rev}}
    end

    def on_checkpoint(nil, _ctx), do: :keep

    @impl Jido.Plugin
    def on_restore(%{id: id}, _ctx) do
      {:ok, %{id: id, restored: true}}
    end
  end

  defmodule DropPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "drop_plugin",
      state_key: :transient,
      actions: []

    @impl Jido.Plugin
    def on_checkpoint(_state, _ctx), do: :drop
  end

  describe "checkpoint hooks" do
    test "default on_checkpoint returns :keep" do
      assert BasicPlugin.on_checkpoint(%{some: :state}, %{}) == :keep
    end

    test "default on_restore returns {:ok, nil}" do
      assert BasicPlugin.on_restore(%{id: "123"}, %{}) == {:ok, nil}
    end

    test "plugin can externalize state during checkpoint" do
      state = %{id: "thread-1", rev: 5}

      assert {:externalize, :ext_pointer, %{id: "thread-1", rev: 5}} =
               ExternalizePlugin.on_checkpoint(state, %{})
    end

    test "plugin can keep nil state during checkpoint" do
      assert :keep = ExternalizePlugin.on_checkpoint(nil, %{})
    end

    test "plugin can restore from pointer" do
      assert {:ok, %{id: "thread-1", restored: true}} =
               ExternalizePlugin.on_restore(%{id: "thread-1"}, %{})
    end

    test "plugin can drop state during checkpoint" do
      assert :drop = DropPlugin.on_checkpoint(%{temp: :data}, %{})
    end
  end

  describe "singleton option" do
    test "singleton defaults to false for regular plugins" do
      refute BasicPlugin.singleton?()
      refute FullPlugin.singleton?()
    end

    test "singleton? returns true when configured" do
      assert SingletonPlugin.singleton?()
    end

    test "singleton is included in manifest" do
      assert SingletonPlugin.manifest().singleton == true
      assert BasicPlugin.manifest().singleton == false
    end
  end
end
