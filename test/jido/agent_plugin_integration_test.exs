defmodule JidoTest.AgentPluginIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Schema
  alias Jido.Plugin.Spec

  # =============================================================================
  # Test Fixtures - Actions
  # =============================================================================

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.StateOp

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter_plugin, :count]) || 0
      {:ok, %{}, %StateOp.SetPath{path: [:counter_plugin, :count], value: current + amount}}
    end
  end

  defmodule DecrementAction do
    @moduledoc false
    use Jido.Action,
      name: "decrement",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.StateOp

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter_plugin, :count]) || 0
      {:ok, %{}, %StateOp.SetPath{path: [:counter_plugin, :count], value: current - amount}}
    end
  end

  defmodule GreetAction do
    @moduledoc false
    use Jido.Action,
      name: "greet",
      schema: Zoi.object(%{name: Zoi.string() |> Zoi.default("World")})

    alias Jido.Agent.StateOp

    def run(%{name: name}, _context) do
      {:ok, %{},
       %StateOp.SetPath{path: [:greeter_plugin, :last_greeting], value: "Hello, #{name}!"}}
    end
  end

  defmodule SetModeAction do
    @moduledoc false
    use Jido.Action,
      name: "set_mode",
      schema: Zoi.object(%{mode: Zoi.atom()})

    alias Jido.Agent.StateOp

    def run(%{mode: mode}, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:mode_plugin, :current_mode], value: mode}}
    end
  end

  defmodule SimpleAction do
    @moduledoc false
    use Jido.Action,
      name: "simple_action",
      schema: []

    def run(_params, _context), do: {:ok, %{executed: true}}
  end

  # =============================================================================
  # Test Fixtures - Plugins
  # =============================================================================

  defmodule CounterPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "counter_plugin",
      state_key: :counter_plugin,
      actions: [
        JidoTest.AgentPluginIntegrationTest.IncrementAction,
        JidoTest.AgentPluginIntegrationTest.DecrementAction
      ],
      description: "A plugin for counting",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  defmodule GreeterPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "greeter_plugin",
      state_key: :greeter_plugin,
      actions: [JidoTest.AgentPluginIntegrationTest.GreetAction],
      description: "A plugin for greeting",
      schema: Zoi.object(%{last_greeting: Zoi.string() |> Zoi.optional()})
  end

  defmodule ConfigurablePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "configurable_plugin",
      state_key: :configurable,
      actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction],
      description: "A plugin with config",
      config_schema:
        Zoi.object(%{
          enabled: Zoi.boolean() |> Zoi.default(true),
          max_retries: Zoi.integer() |> Zoi.default(3)
        }),
      schema: Zoi.object(%{status: Zoi.atom() |> Zoi.default(:ready)})
  end

  defmodule ModePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "mode_plugin",
      state_key: :mode_plugin,
      actions: [JidoTest.AgentPluginIntegrationTest.SetModeAction],
      schema: Zoi.object(%{current_mode: Zoi.atom() |> Zoi.default(:normal)})
  end

  defmodule MinimalPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "minimal_plugin",
      state_key: :minimal,
      actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction]
  end

  # =============================================================================
  # Test Fixtures - Agents
  # =============================================================================

  defmodule SinglePluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "single_skill_agent",
      default_plugins: false,
      plugins: [JidoTest.AgentPluginIntegrationTest.CounterPlugin]
  end

  defmodule MultiPluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "multi_skill_agent",
      default_plugins: false,
      plugins: [
        JidoTest.AgentPluginIntegrationTest.CounterPlugin,
        JidoTest.AgentPluginIntegrationTest.GreeterPlugin
      ]
  end

  defmodule ConfiguredPluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_skill_agent",
      default_plugins: false,
      plugins: [
        {JidoTest.AgentPluginIntegrationTest.ConfigurablePlugin,
         %{enabled: false, max_retries: 5}}
      ]
  end

  defmodule MixedSchemaAgent do
    @moduledoc false
    use Jido.Agent,
      name: "mixed_schema_agent",
      default_plugins: false,
      schema: [
        base_counter: [type: :integer, default: 100],
        base_mode: [type: :atom, default: :initial]
      ],
      plugins: [JidoTest.AgentPluginIntegrationTest.CounterPlugin]
  end

  defmodule ThreePluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "three_skill_agent",
      default_plugins: false,
      plugins: [
        JidoTest.AgentPluginIntegrationTest.CounterPlugin,
        JidoTest.AgentPluginIntegrationTest.GreeterPlugin,
        JidoTest.AgentPluginIntegrationTest.ModePlugin
      ]
  end

  defmodule MinimalPluginAgent do
    @moduledoc false
    use Jido.Agent,
      name: "minimal_skill_agent",
      default_plugins: false,
      plugins: [JidoTest.AgentPluginIntegrationTest.MinimalPlugin]
  end

  # =============================================================================
  # Tests: Agent with Single Skill
  # =============================================================================

  describe "agent with single plugin" do
    test "skills/0 returns the plugin modules" do
      modules = SinglePluginAgent.plugins()

      assert length(modules) == 1
      assert CounterPlugin in modules
    end

    test "plugin_specs/0 returns the skill spec" do
      specs = SinglePluginAgent.plugin_specs()

      assert length(specs) == 1
      [spec] = specs
      assert %Spec{} = spec
      assert spec.module == CounterPlugin
      assert spec.name == "counter_plugin"
      assert spec.state_key == :counter_plugin
    end

    test "actions/0 includes plugin actions" do
      actions = SinglePluginAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert length(actions) == 2
    end

    test "schema/0 returns merged schema with plugin nested under state_key" do
      schema = SinglePluginAgent.schema()

      assert is_struct(schema)
      keys = Schema.known_keys(schema)
      assert :counter_plugin in keys
    end

    test "new/0 initializes plugin state with defaults under state_key" do
      agent = SinglePluginAgent.new()

      assert agent.state[:counter_plugin] != nil
      assert agent.state[:counter_plugin][:count] == 0
    end

    test "new/1 with custom state merges correctly" do
      agent = SinglePluginAgent.new(state: %{counter_plugin: %{count: 10}})

      assert agent.state[:counter_plugin][:count] == 10
    end
  end

  # =============================================================================
  # Tests: Agent with Multiple Skills
  # =============================================================================

  describe "agent with multiple plugins" do
    test "skills/0 returns both plugin modules (deduplicated)" do
      modules = MultiPluginAgent.plugins()

      assert length(modules) == 2
      assert CounterPlugin in modules
      assert GreeterPlugin in modules
    end

    test "plugin_specs/0 returns both skill specs" do
      specs = MultiPluginAgent.plugin_specs()

      assert length(specs) == 2
      modules = Enum.map(specs, & &1.module)
      assert CounterPlugin in modules
      assert GreeterPlugin in modules
    end

    test "actions/0 aggregates actions from both plugins" do
      actions = MultiPluginAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert GreetAction in actions
      assert length(actions) == 3
    end

    test "new/0 initializes state for both skills" do
      agent = MultiPluginAgent.new()

      assert agent.state[:counter_plugin] != nil
      assert agent.state[:counter_plugin][:count] == 0

      assert agent.state[:greeter_plugin] != nil
      assert agent.state[:greeter_plugin][:last_greeting] == nil
    end

    test "plugin states are isolated under their state_keys" do
      agent = MultiPluginAgent.new()

      counter_state = agent.state[:counter_plugin]
      greeter_state = agent.state[:greeter_plugin]

      assert is_map(counter_state)
      assert is_map(greeter_state)
      assert Map.keys(counter_state) != Map.keys(greeter_state)
    end
  end

  describe "agent with three plugins" do
    test "all plugin modules are returned" do
      modules = ThreePluginAgent.plugins()

      assert length(modules) == 3
      assert CounterPlugin in modules
      assert GreeterPlugin in modules
      assert ModePlugin in modules
    end

    test "actions from all plugins are aggregated" do
      actions = ThreePluginAgent.actions()

      assert IncrementAction in actions
      assert DecrementAction in actions
      assert GreetAction in actions
      assert SetModeAction in actions
    end

    test "all plugin states are initialized" do
      agent = ThreePluginAgent.new()

      assert agent.state[:counter_plugin][:count] == 0
      assert agent.state[:greeter_plugin][:last_greeting] == nil
      assert agent.state[:mode_plugin][:current_mode] == :normal
    end
  end

  # =============================================================================
  # Tests: Plugin with Config
  # =============================================================================

  describe "plugin with config" do
    test "plugin_config/1 returns the config" do
      config = ConfiguredPluginAgent.plugin_config(ConfigurablePlugin)

      assert config != nil
      assert config[:enabled] == false
      assert config[:max_retries] == 5
    end

    test "plugin_config/1 returns nil for unknown plugin module" do
      config = ConfiguredPluginAgent.plugin_config(CounterPlugin)

      assert config == nil
    end

    test "plugin_spec contains the config" do
      [spec] = ConfiguredPluginAgent.plugin_specs()

      assert spec.config[:enabled] == false
      assert spec.config[:max_retries] == 5
    end

    test "config_schema is available on skill" do
      config_schema = ConfigurablePlugin.config_schema()

      assert config_schema != nil
    end

    test "plugin state is initialized with defaults" do
      agent = ConfiguredPluginAgent.new()

      assert agent.state[:configurable][:status] == :ready
    end
  end

  # =============================================================================
  # Tests: State Isolation
  # =============================================================================

  describe "state isolation" do
    test "plugin_state/2 returns only the plugin's state" do
      agent = MultiPluginAgent.new()

      counter_state = MultiPluginAgent.plugin_state(agent, CounterPlugin)
      greeter_state = MultiPluginAgent.plugin_state(agent, GreeterPlugin)

      assert counter_state == %{count: 0}
      assert greeter_state == %{}
    end

    test "plugin_state/2 returns nil for unknown plugin" do
      agent = MultiPluginAgent.new()

      result = MultiPluginAgent.plugin_state(agent, ConfigurablePlugin)

      assert result == nil
    end

    test "executing an action modifies only its plugin's namespace" do
      agent = MultiPluginAgent.new()

      {updated, _directives} = MultiPluginAgent.cmd(agent, {IncrementAction, %{amount: 5}})

      assert updated.state[:counter_plugin][:count] == 5
      assert updated.state[:greeter_plugin][:last_greeting] == nil
    end

    test "executing multiple actions maintains isolation" do
      agent = MultiPluginAgent.new()

      {agent2, _} = MultiPluginAgent.cmd(agent, {IncrementAction, %{amount: 3}})
      {agent3, _} = MultiPluginAgent.cmd(agent2, {GreetAction, %{name: "Alice"}})
      {agent4, _} = MultiPluginAgent.cmd(agent3, {IncrementAction, %{amount: 2}})

      assert agent4.state[:counter_plugin][:count] == 5
      assert agent4.state[:greeter_plugin][:last_greeting] == "Hello, Alice!"
    end
  end

  # =============================================================================
  # Tests: Introspection APIs
  # =============================================================================

  describe "introspection APIs" do
    test "skills/0 returns list of plugin modules (deduplicated)" do
      modules = MultiPluginAgent.plugins()

      assert is_list(modules)
      assert Enum.all?(modules, &is_atom/1)
      assert length(modules) == 2
    end

    test "plugin_specs/0 returns list of skill specs" do
      specs = MultiPluginAgent.plugin_specs()

      assert is_list(specs)
      assert Enum.all?(specs, &match?(%Spec{}, &1))
    end

    test "actions/0 returns list of action modules" do
      actions = MultiPluginAgent.actions()

      assert is_list(actions)
      assert Enum.all?(actions, &is_atom/1)
    end

    test "actions/0 returns empty list for agent without plugins" do
      defmodule NoPluginAgent do
        use Jido.Agent,
          name: "no_skill_agent",
          default_plugins: false
      end

      assert NoPluginAgent.actions() == []
    end

    test "plugin_config/1 with valid plugin returns config map" do
      config = ConfiguredPluginAgent.plugin_config(ConfigurablePlugin)

      assert is_map(config)
    end

    test "plugin_config/1 with invalid plugin returns nil" do
      config = ConfiguredPluginAgent.plugin_config(NonExistentModule)

      assert config == nil
    end

    test "plugin_state/2 with valid plugin returns state map" do
      agent = SinglePluginAgent.new()
      state = SinglePluginAgent.plugin_state(agent, CounterPlugin)

      assert is_map(state)
      assert state[:count] == 0
    end

    test "plugin_state/2 with invalid plugin returns nil" do
      agent = SinglePluginAgent.new()
      state = SinglePluginAgent.plugin_state(agent, NonExistentModule)

      assert state == nil
    end

    test "capabilities/0 returns empty list for agents without capability-declaring skills" do
      capabilities = SinglePluginAgent.capabilities()

      assert capabilities == []
    end

    test "signal_types/0 returns empty list for agents without routes" do
      signal_types = SinglePluginAgent.signal_types()

      assert signal_types == []
    end
  end

  # =============================================================================
  # Tests: Capabilities and Signal Types
  # =============================================================================

  describe "capabilities and signal_types introspection" do
    defmodule SlackCapabilityPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "slack_cap",
        state_key: :slack_cap,
        actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction],
        capabilities: [:messaging, :channel_management],
        routes: [
          {"post", JidoTest.AgentPluginIntegrationTest.SimpleAction},
          {"channels.list", JidoTest.AgentPluginIntegrationTest.SimpleAction}
        ]
    end

    defmodule OpenAICapabilityPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "openai_cap",
        state_key: :openai_cap,
        actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction],
        capabilities: [:chat, :embeddings, :messaging],
        routes: [
          {"chat", JidoTest.AgentPluginIntegrationTest.SimpleAction},
          {"embeddings", JidoTest.AgentPluginIntegrationTest.SimpleAction}
        ]
    end

    defmodule CapabilityAgent do
      @moduledoc false
      use Jido.Agent,
        name: "capability_agent",
        default_plugins: false,
        plugins: [
          JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin,
          JidoTest.AgentPluginIntegrationTest.OpenAICapabilityPlugin
        ]
    end

    test "capabilities/0 returns union of all skill capabilities (deduplicated)" do
      capabilities = CapabilityAgent.capabilities()

      assert is_list(capabilities)
      assert :messaging in capabilities
      assert :channel_management in capabilities
      assert :chat in capabilities
      assert :embeddings in capabilities
      assert length(Enum.filter(capabilities, &(&1 == :messaging))) == 1
    end

    test "signal_types/0 returns all expanded route signal types" do
      signal_types = CapabilityAgent.signal_types()

      assert is_list(signal_types)
      assert "slack_cap.post" in signal_types
      assert "slack_cap.channels.list" in signal_types
      assert "openai_cap.chat" in signal_types
      assert "openai_cap.embeddings" in signal_types
    end

    test "signal_types/0 returns fully-prefixed routes for aliased plugins" do
      defmodule AliasedCapAgent do
        @moduledoc false
        use Jido.Agent,
          name: "aliased_cap_agent",
          default_plugins: false,
          plugins: [
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :support},
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :sales}
          ]
      end

      signal_types = AliasedCapAgent.signal_types()

      assert "support.slack_cap.post" in signal_types
      assert "support.slack_cap.channels.list" in signal_types
      assert "sales.slack_cap.post" in signal_types
      assert "sales.slack_cap.channels.list" in signal_types
    end

    test "skills/0 deduplicates modules for multi-instance plugins" do
      defmodule MultiInstanceCapAgent do
        @moduledoc false
        use Jido.Agent,
          name: "multi_instance_cap_agent",
          default_plugins: false,
          plugins: [
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :support},
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :sales},
            JidoTest.AgentPluginIntegrationTest.OpenAICapabilityPlugin
          ]
      end

      modules = MultiInstanceCapAgent.plugins()

      assert length(modules) == 2
      assert SlackCapabilityPlugin in modules
      assert OpenAICapabilityPlugin in modules
    end

    test "capabilities/0 returns deduplicated capabilities from multiple instances" do
      defmodule MultiInstanceCapAgent2 do
        @moduledoc false
        use Jido.Agent,
          name: "multi_instance_cap_agent2",
          default_plugins: false,
          plugins: [
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :support},
            {JidoTest.AgentPluginIntegrationTest.SlackCapabilityPlugin, as: :sales}
          ]
      end

      capabilities = MultiInstanceCapAgent2.capabilities()

      assert :messaging in capabilities
      assert :channel_management in capabilities
      assert length(Enum.filter(capabilities, &(&1 == :messaging))) == 1
    end
  end

  # =============================================================================
  # Tests: Schema Merging
  # =============================================================================

  describe "schema merging" do
    test "merged schema contains plugin state_keys" do
      schema = MixedSchemaAgent.schema()
      keys = Schema.known_keys(schema)

      assert :counter_plugin in keys
    end

    test "defaults from both base and skill are applied in new/0" do
      agent = MixedSchemaAgent.new()

      assert agent.state[:base_counter] == 100
      assert agent.state[:base_mode] == :initial
      assert agent.state[:counter_plugin][:count] == 0
    end

    test "base schema fields and plugin schema fields coexist" do
      agent = MixedSchemaAgent.new(state: %{base_counter: 50})

      assert agent.state[:base_counter] == 50
      assert agent.state[:base_mode] == :initial
      assert agent.state[:counter_plugin][:count] == 0
    end

    test "skill without schema works" do
      agent = MinimalPluginAgent.new()

      assert agent.state[:minimal] == %{}
    end

    test "agent schema/0 returns the merged schema" do
      schema = SinglePluginAgent.schema()

      assert is_struct(schema)
    end
  end

  # =============================================================================
  # Tests: cmd/2 with Skill Actions
  # =============================================================================

  describe "cmd/2 with plugin actions" do
    test "executes skill action module" do
      agent = SinglePluginAgent.new()

      {updated, directives} = SinglePluginAgent.cmd(agent, IncrementAction)

      assert updated.state[:counter_plugin][:count] == 1
      assert directives == []
    end

    test "executes skill action with params" do
      agent = SinglePluginAgent.new()

      {updated, directives} = SinglePluginAgent.cmd(agent, {IncrementAction, %{amount: 10}})

      assert updated.state[:counter_plugin][:count] == 10
      assert directives == []
    end

    test "executes list of plugin actions" do
      agent = SinglePluginAgent.new()

      {updated, directives} =
        SinglePluginAgent.cmd(agent, [
          {IncrementAction, %{amount: 5}},
          {IncrementAction, %{amount: 3}},
          DecrementAction
        ])

      assert updated.state[:counter_plugin][:count] == 7
      assert directives == []
    end

    test "works with actions from multiple skills" do
      agent = MultiPluginAgent.new()

      {updated, _} =
        MultiPluginAgent.cmd(agent, [
          {IncrementAction, %{amount: 10}},
          {GreetAction, %{name: "Test"}}
        ])

      assert updated.state[:counter_plugin][:count] == 10
      assert updated.state[:greeter_plugin][:last_greeting] == "Hello, Test!"
    end

    test "state updates persist across multiple cmd calls" do
      agent = SinglePluginAgent.new()

      {agent2, _} = SinglePluginAgent.cmd(agent, {IncrementAction, %{amount: 5}})
      {agent3, _} = SinglePluginAgent.cmd(agent2, {IncrementAction, %{amount: 3}})
      {agent4, _} = SinglePluginAgent.cmd(agent3, {DecrementAction, %{amount: 2}})

      assert agent4.state[:counter_plugin][:count] == 6
    end

    test "cmd/2 with Instruction struct works" do
      agent = SinglePluginAgent.new()

      {:ok, instruction} =
        Jido.Instruction.new(%{action: IncrementAction, params: %{amount: 7}})

      {updated, _directives} = SinglePluginAgent.cmd(agent, instruction)

      assert updated.state[:counter_plugin][:count] == 7
    end
  end

  # =============================================================================
  # Tests: Edge Cases
  # =============================================================================

  describe "edge cases" do
    test "agent with skill that has no schema initializes with empty map" do
      agent = MinimalPluginAgent.new()

      assert agent.state[:minimal] == %{}
    end

    test "accessing plugin state for plugin without schema returns empty map" do
      agent = MinimalPluginAgent.new()
      state = MinimalPluginAgent.plugin_state(agent, MinimalPlugin)

      assert state == %{}
    end

    test "plugin actions list is deduplicated" do
      defmodule DuplicateActionPlugin do
        use Jido.Plugin,
          name: "dup_plugin",
          state_key: :dup,
          actions: [
            JidoTest.AgentPluginIntegrationTest.SimpleAction,
            JidoTest.AgentPluginIntegrationTest.SimpleAction
          ]
      end

      defmodule DupAgent do
        use Jido.Agent,
          name: "dup_agent",
          default_plugins: false,
          plugins: [JidoTest.AgentPluginIntegrationTest.DuplicateActionPlugin]
      end

      actions = DupAgent.actions()
      assert length(actions) == 1
      assert SimpleAction in actions
    end

    test "multiple skills with same action module works" do
      defmodule SharedActionPluginA do
        use Jido.Plugin,
          name: "shared_a",
          state_key: :shared_a,
          actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction]
      end

      defmodule SharedActionPluginB do
        use Jido.Plugin,
          name: "shared_b",
          state_key: :shared_b,
          actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction]
      end

      defmodule SharedActionAgent do
        use Jido.Agent,
          name: "shared_action_agent",
          default_plugins: false,
          plugins: [
            JidoTest.AgentPluginIntegrationTest.SharedActionPluginA,
            JidoTest.AgentPluginIntegrationTest.SharedActionPluginB
          ]
      end

      actions = SharedActionAgent.actions()
      assert length(actions) == 1
      assert SimpleAction in actions
    end

    test "agent metadata is preserved with plugins" do
      agent = MultiPluginAgent.new()

      assert agent.name == "multi_skill_agent"
      assert is_binary(agent.id)
    end
  end

  # =============================================================================
  # Tests: Multi-Instance Plugins (as: option)
  # =============================================================================

  describe "multi-instance plugins with as: option" do
    defmodule SlackPlugin do
      @moduledoc false
      use Jido.Plugin,
        name: "slack",
        state_key: :slack,
        actions: [JidoTest.AgentPluginIntegrationTest.SimpleAction],
        schema:
          Zoi.object(%{
            token: Zoi.string() |> Zoi.optional(),
            channel: Zoi.string() |> Zoi.optional()
          })
    end

    defmodule MultiSlackAgent do
      @moduledoc false
      use Jido.Agent,
        name: "multi_slack_agent",
        default_plugins: false,
        plugins: [
          {JidoTest.AgentPluginIntegrationTest.SlackPlugin, as: :support, token: "support-token"},
          {JidoTest.AgentPluginIntegrationTest.SlackPlugin, as: :sales, token: "sales-token"}
        ]
    end

    defmodule MixedInstanceAgent do
      @moduledoc false
      use Jido.Agent,
        name: "mixed_instance_agent",
        default_plugins: false,
        plugins: [
          JidoTest.AgentPluginIntegrationTest.SlackPlugin,
          {JidoTest.AgentPluginIntegrationTest.SlackPlugin, as: :support, token: "support-token"}
        ]
    end

    test "plugin_instances/0 returns Instance structs" do
      instances = MultiSlackAgent.plugin_instances()

      assert length(instances) == 2
      assert Enum.all?(instances, &match?(%Jido.Plugin.Instance{}, &1))
    end

    test "instances have different derived state_keys" do
      instances = MultiSlackAgent.plugin_instances()

      state_keys = Enum.map(instances, & &1.state_key)
      assert :slack_support in state_keys
      assert :slack_sales in state_keys
    end

    test "instances have different route_prefixes" do
      instances = MultiSlackAgent.plugin_instances()

      prefixes = Enum.map(instances, & &1.route_prefix)
      assert "support.slack" in prefixes
      assert "sales.slack" in prefixes
    end

    test "agent state has separate namespaces per instance" do
      agent = MultiSlackAgent.new()

      assert Map.has_key?(agent.state, :slack_support)
      assert Map.has_key?(agent.state, :slack_sales)
    end

    test "plugin_config/1 with {module, alias} tuple returns correct config" do
      assert MultiSlackAgent.plugin_config({SlackPlugin, :support}) == %{token: "support-token"}
      assert MultiSlackAgent.plugin_config({SlackPlugin, :sales}) == %{token: "sales-token"}
    end

    test "plugin_state/2 with {module, alias} tuple returns correct state" do
      agent = MultiSlackAgent.new()

      support_state = MultiSlackAgent.plugin_state(agent, {SlackPlugin, :support})
      sales_state = MultiSlackAgent.plugin_state(agent, {SlackPlugin, :sales})

      assert is_map(support_state)
      assert is_map(sales_state)
    end

    test "mixed instances (with and without as:) have different state_keys" do
      instances = MixedInstanceAgent.plugin_instances()

      state_keys = Enum.map(instances, & &1.state_key)
      assert :slack in state_keys
      assert :slack_support in state_keys
    end

    test "plugin_config/1 with just module finds default instance first" do
      config = MixedInstanceAgent.plugin_config(SlackPlugin)
      assert config == %{}
    end

    test "plugin_state/2 with just module finds default instance first" do
      agent = MixedInstanceAgent.new()
      state = MixedInstanceAgent.plugin_state(agent, SlackPlugin)
      assert is_map(state)
    end
  end

  describe "duplicate state_key detection with as: option" do
    test "same skill without as: twice raises duplicate error" do
      assert_raise CompileError, ~r/Duplicate plugin state_keys/, fn ->
        defmodule DuplicateNoAsAgent do
          use Jido.Agent,
            name: "duplicate_no_as",
            plugins: [
              JidoTest.AgentPluginIntegrationTest.CounterPlugin,
              JidoTest.AgentPluginIntegrationTest.CounterPlugin
            ]
        end
      end
    end

    test "same skill with same as: value raises duplicate error" do
      assert_raise CompileError, ~r/Duplicate plugin state_keys/, fn ->
        defmodule DuplicateSameAsAgent do
          use Jido.Agent,
            name: "duplicate_same_as",
            plugins: [
              {JidoTest.AgentPluginIntegrationTest.CounterPlugin, as: :primary},
              {JidoTest.AgentPluginIntegrationTest.CounterPlugin, as: :primary}
            ]
        end
      end
    end

    test "same skill with different as: values works" do
      defmodule DifferentAsAgent do
        use Jido.Agent,
          name: "different_as_agent",
          default_plugins: false,
          plugins: [
            {JidoTest.AgentPluginIntegrationTest.CounterPlugin, as: :primary},
            {JidoTest.AgentPluginIntegrationTest.CounterPlugin, as: :secondary}
          ]
      end

      instances = DifferentAsAgent.plugin_instances()
      assert length(instances) == 2

      state_keys = Enum.map(instances, & &1.state_key)
      assert :counter_plugin_primary in state_keys
      assert :counter_plugin_secondary in state_keys
    end
  end
end
