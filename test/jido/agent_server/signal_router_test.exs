defmodule JidoTest.AgentServer.SignalRouterTest do
  use ExUnit.Case, async: true

  alias Jido.AgentServer.SignalRouter
  alias Jido.AgentServer.State
  alias Jido.AgentServer.State.Lifecycle
  alias Jido.Signal.Router, as: JidoRouter

  # =============================================================================
  # Test Fixtures - Actions
  # =============================================================================

  defmodule TestAction do
    @moduledoc false
    use Jido.Action,
      name: "test_action",
      schema: []

    def run(_params, _ctx), do: {:ok, %{}}
  end

  defmodule AnotherAction do
    @moduledoc false
    use Jido.Action,
      name: "another_action",
      schema: []

    def run(_params, _ctx), do: {:ok, %{}}
  end

  # =============================================================================
  # Test Fixtures - Strategies
  # =============================================================================

  defmodule StrategyWithRoutes do
    @moduledoc false
    use Jido.Agent.Strategy

    @impl true
    def cmd(agent, _instructions, _ctx), do: {agent, []}

    @impl true
    def signal_routes(_ctx) do
      [
        {"strategy.action", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"strategy.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, 75}
      ]
    end
  end

  defmodule StrategyWithoutRoutes do
    @moduledoc "Strategy that does NOT export signal_routes/1"
    @behaviour Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx), do: {agent, []}

    @impl true
    def tick(agent, _ctx), do: {agent, []}

    @impl true
    def cmd(agent, _instructions, _ctx), do: {agent, []}
  end

  # =============================================================================
  # Test Fixtures - Plugins
  # =============================================================================

  defmodule PluginWithRouter do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_router",
      state_key: :router_plugin,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction]

    @impl Jido.Plugin
    def signal_routes(_config) do
      [
        {"plugin.custom", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"plugin.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, -20}
      ]
    end
  end

  defmodule PluginWithRouterOpts do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_router_opts",
      state_key: :router_opts_plugin,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction]

    @impl Jido.Plugin
    def signal_routes(_config) do
      [
        {"plugin.opts", JidoTest.AgentServer.SignalRouterTest.TestAction, priority: -30}
      ]
    end
  end

  defmodule PluginReturningNil do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_returning_nil",
      state_key: :nil_plugin,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction],
      signal_patterns: ["nil.*"]

    @impl Jido.Plugin
    def signal_routes(_config), do: []
  end

  defmodule PluginReturningNonList do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_returning_non_list",
      state_key: :non_list_plugin,
      actions: [JidoTest.AgentServer.SignalRouterTest.TestAction],
      signal_patterns: ["nonlist.*"]

    @impl Jido.Plugin
    def signal_routes(_config), do: :not_a_list
  end

  defmodule PluginWithPatterns do
    @moduledoc false
    use Jido.Plugin,
      name: "plugin_with_patterns",
      state_key: :pattern_plugin,
      actions: [
        JidoTest.AgentServer.SignalRouterTest.TestAction,
        JidoTest.AgentServer.SignalRouterTest.AnotherAction
      ],
      signal_routes: [
        {"pattern.one", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"pattern.two", JidoTest.AgentServer.SignalRouterTest.AnotherAction}
      ]
  end

  # =============================================================================
  # Test Fixtures - Agents
  # =============================================================================

  defmodule AgentWithRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_routes",
      schema: []

    def signal_routes(_ctx) do
      [
        {"agent.action", JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"agent.priority", JidoTest.AgentServer.SignalRouterTest.TestAction, 10}
      ]
    end
  end

  defmodule AgentWithoutRoutes do
    @moduledoc "Agent that does NOT export signal_routes/1"
    use Jido.Agent,
      name: "agent_without_routes",
      schema: []
  end

  defmodule AgentWithStrategy do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_strategy",
      strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithRoutes,
      schema: []

    def signal_routes(_ctx) do
      [{"agent.route", JidoTest.AgentServer.SignalRouterTest.TestAction}]
    end
  end

  defmodule AgentWithStrategyNoRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_strategy_no_routes",
      strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithoutRoutes,
      schema: []

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithPlugins do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_plugins",
      schema: [],
      plugins: [
        JidoTest.AgentServer.SignalRouterTest.PluginWithRouter,
        JidoTest.AgentServer.SignalRouterTest.PluginWithPatterns
      ]

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithNilRouterPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_nil_router_plugin",
      schema: [],
      plugins: [JidoTest.AgentServer.SignalRouterTest.PluginReturningNil]

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithPluginRouteOpts do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_plugin_route_opts",
      schema: [],
      plugins: [JidoTest.AgentServer.SignalRouterTest.PluginWithRouterOpts]

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithNonListRouterPlugin do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_non_list_router_plugin",
      schema: [],
      plugins: [JidoTest.AgentServer.SignalRouterTest.PluginReturningNonList]

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithMatchFnRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_match_fn_routes",
      schema: []

    def signal_routes(_ctx) do
      [
        {"match.three", &match_large_amount/1, JidoTest.AgentServer.SignalRouterTest.TestAction},
        {"match.four", &match_large_amount/1, JidoTest.AgentServer.SignalRouterTest.TestAction,
         15}
      ]
    end

    defp match_large_amount(signal) do
      Map.get(signal.data, :amount, 0) > 100
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp build_test_state(agent_module) do
    agent = agent_module.new(%{id: "test-#{System.unique_integer([:positive])}"})

    {:ok, lifecycle} = Lifecycle.new([])

    attrs = %{
      id: agent.id,
      agent_module: agent_module,
      agent: agent,
      status: :idle,
      processing: false,
      queue: :queue.new(),
      parent: nil,
      children: %{},
      on_parent_death: :stop,
      jido: :test_jido,
      default_dispatch: nil,
      error_policy: :log_only,
      max_queue_size: 10_000,
      registry: nil,
      spawn_fun: nil,
      cron_jobs: %{},
      error_count: 0,
      metrics: %{},
      completion_waiters: %{},
      lifecycle: lifecycle
    }

    {:ok, state} = Zoi.parse(State.schema(), attrs)
    state
  end

  # =============================================================================
  # Tests
  # =============================================================================

  describe "build/1 with agent routes" do
    test "builds router from agent signal_routes/1" do
      state = build_test_state(AgentWithRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count > 0
    end

    test "returns empty router when agent doesn't export signal_routes/1" do
      state = build_test_state(AgentWithoutRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 0
    end
  end

  describe "build/1 with strategy routes" do
    test "builds router from strategy signal_routes/1" do
      state = build_test_state(AgentWithStrategy)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have routes from both strategy and agent
      assert router.route_count >= 2
    end

    test "handles strategy without signal_routes/1 function" do
      state = build_test_state(AgentWithStrategyNoRoutes)
      router = SignalRouter.build(state)

      # Should still build successfully, just without strategy routes
      assert %JidoRouter.Router{} = router
    end
  end

  describe "build/1 with plugin routes" do
    test "builds router from plugin signal_routes/1 function" do
      state = build_test_state(AgentWithPlugins)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have routes from plugin signal_routes and pattern-based routes
      assert router.route_count > 0
    end

    test "handles plugin signal_routes/1 returning empty list - falls back to pattern routes" do
      state = build_test_state(AgentWithNilRouterPlugin)
      router = SignalRouter.build(state)

      # Should generate pattern-based routes instead
      assert %JidoRouter.Router{} = router
      # Pattern routes: signal_patterns ["nil.*"] x actions [TestAction]
      assert router.route_count == 1
    end

    test "handles plugin signal_routes/1 returning non-list value - falls back to pattern routes" do
      state = build_test_state(AgentWithNonListRouterPlugin)
      router = SignalRouter.build(state)

      # Should generate pattern-based routes instead
      assert %JidoRouter.Router{} = router
      # Pattern routes: signal_patterns ["nonlist.*"] x actions [TestAction]
      assert router.route_count == 1
    end

    test "supports plugin signal_routes/1 tuples with keyword opts" do
      state = build_test_state(AgentWithPluginRouteOpts)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 1

      signal = Jido.Signal.new!("plugin.opts", %{}, source: "/test")
      assert {:ok, [TestAction]} = JidoRouter.route(router, signal)
    end

    test "generates routes from plugin routes definition" do
      # PluginWithPatterns has 2 explicit routes, PluginWithRouter has 2 custom router routes
      state = build_test_state(AgentWithPlugins)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # PluginWithRouter has 2 custom routes, PluginWithPatterns has 2 explicit routes
      # Total: 2 + 2 = 4 routes
      assert router.route_count == 4
    end
  end

  describe "build/1 with match functions" do
    test "normalizes 3-tuple routes with match functions" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Should have 2 routes with match functions
      assert router.route_count == 2
    end

    test "normalizes 4-tuple routes with match functions and priority" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 2
    end
  end

  describe "build/1 routing with match functions" do
    test "routes match when match function returns true" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      # Signal with amount > 100 should match
      signal = Jido.Signal.new!("match.three", %{amount: 150}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert length(targets) == 1
      assert TestAction in targets
    end

    test "routes don't match when match function returns false" do
      state = build_test_state(AgentWithMatchFnRoutes)
      router = SignalRouter.build(state)

      # Signal with amount <= 100 should not match
      signal = Jido.Signal.new!("match.three", %{amount: 50}, source: "/test")
      result = JidoRouter.route(router, signal)

      # Should return no match or empty list
      assert result == {:ok, []} or match?({:error, _}, result)
    end
  end

  describe "build/1 priority handling" do
    test "applies default strategy priority (50) to routes without explicit priority" do
      state = build_test_state(AgentWithStrategy)
      router = SignalRouter.build(state)

      # Verify the router was built - we can't easily inspect internal priority
      # but we can verify routes work
      signal = Jido.Signal.new!("strategy.action", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end

    test "applies default agent priority (0) to routes without explicit priority" do
      state = build_test_state(AgentWithRoutes)
      router = SignalRouter.build(state)

      signal = Jido.Signal.new!("agent.action", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end

    test "applies default plugin priority (-10) to routes without explicit priority" do
      state = build_test_state(AgentWithPlugins)
      router = SignalRouter.build(state)

      signal = Jido.Signal.new!("plugin.custom", %{}, source: "/test")
      {:ok, targets} = JidoRouter.route(router, signal)

      assert TestAction in targets
    end
  end

  describe "build/1 combined routes" do
    test "combines routes from strategy, agent, and plugins" do
      # Create an agent that has strategy routes, agent routes, and plugin routes
      defmodule CombinedAgent do
        @moduledoc false
        use Jido.Agent,
          name: "combined_agent",
          strategy: JidoTest.AgentServer.SignalRouterTest.StrategyWithRoutes,
          schema: [],
          plugins: [JidoTest.AgentServer.SignalRouterTest.PluginWithRouter]

        def signal_routes(_ctx) do
          [{"combined.agent", JidoTest.AgentServer.SignalRouterTest.TestAction}]
        end
      end

      state = build_test_state(CombinedAgent)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      # Strategy: 2 routes, Agent: 1 route, Plugin: 2 routes = 5 total
      assert router.route_count == 5
    end
  end

  describe "build/1 error handling" do
    test "returns empty router when no routes are defined" do
      state = build_test_state(AgentWithoutRoutes)
      router = SignalRouter.build(state)

      assert %JidoRouter.Router{} = router
      assert router.route_count == 0
    end
  end
end
