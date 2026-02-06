defmodule JidoTest.TestAgents do
  @moduledoc """
  Shared test agents for Jido test suite.
  """

  # Ensure test actions are compiled before this module
  # (required for compile-time validation in use Jido.Plugin)
  Code.ensure_compiled!(JidoTest.PluginTestAction)
  Code.ensure_compiled!(JidoTest.TestActions.IncrementAction)

  defmodule Minimal do
    @moduledoc false
    use Jido.Agent,
      name: "minimal_agent"

    def signal_routes(_ctx), do: []
  end

  defmodule Counter do
    @moduledoc """
    Standard test agent with counter and messages state.

    Routes:
      - "increment" -> IncrementAction
      - "decrement" -> DecrementAction
      - "record" -> RecordAction
      - "slow" -> SlowAction
      - "fail" -> FailingAction
    """
    use Jido.Agent,
      name: "counter_agent",
      description: "Test agent with counter and message tracking",
      schema: [
        counter: [type: :integer, default: 0],
        messages: [type: {:list, :any}, default: []]
      ]

    def signal_routes(_ctx) do
      [
        {"increment", JidoTest.TestActions.IncrementAction},
        {"decrement", JidoTest.TestActions.DecrementAction},
        {"record", JidoTest.TestActions.RecordAction},
        {"slow", JidoTest.TestActions.SlowAction},
        {"fail", JidoTest.TestActions.FailingAction}
      ]
    end
  end

  defmodule Basic do
    @moduledoc false
    use Jido.Agent,
      name: "basic_agent",
      description: "A basic test agent",
      category: "test",
      tags: ["test", "basic"],
      vsn: "1.0.0",
      schema: [
        counter: [type: :integer, default: 0],
        status: [type: :atom, default: :idle]
      ]

    def signal_routes(_ctx), do: []
  end

  defmodule Hook do
    @moduledoc false
    use Jido.Agent,
      name: "hook_agent",
      schema: [
        counter: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx), do: []

    def on_after_cmd(agent, _action, directives) do
      {:ok, %{agent | state: Map.put(agent.state, :hook_called, true)}, directives}
    end
  end

  defmodule CountingStrategy do
    @moduledoc false
    @behaviour Jido.Agent.Strategy

    alias Jido.Agent.Strategy.Direct

    @impl true
    def init(agent, _ctx), do: {agent, []}

    @impl true
    def tick(agent, _ctx), do: {agent, []}

    @impl true
    def cmd(agent, action, ctx) do
      count = Map.get(agent.state, :strategy_count, 0)
      agent = %{agent | state: Map.put(agent.state, :strategy_count, count + 1)}
      Direct.cmd(agent, action, ctx)
    end
  end

  defmodule InitDirectiveStrategy do
    @moduledoc "Strategy that emits directives from init/2 for testing"
    use Jido.Agent.Strategy

    @impl true
    def init(agent, _ctx) do
      new_state = Map.put(agent.state, :__strategy__, %{initialized: true})
      agent = %{agent | state: new_state}

      signal = Jido.Signal.new!("strategy.initialized", %{}, source: "/strategy")
      {agent, [%Jido.Agent.Directive.Emit{signal: signal}]}
    end

    @impl true
    def cmd(agent, _instructions, _ctx) do
      {agent, []}
    end
  end

  defmodule CustomStrategy do
    @moduledoc false
    use Jido.Agent,
      name: "custom_strategy_agent",
      strategy: JidoTest.TestAgents.CountingStrategy

    def signal_routes(_ctx), do: []
  end

  defmodule StrategyWithOpts do
    @moduledoc false
    use Jido.Agent,
      name: "strategy_opts_agent",
      strategy: {JidoTest.TestAgents.CountingStrategy, max_depth: 5}

    def signal_routes(_ctx), do: []
  end

  defmodule ZoiSchema do
    @moduledoc false
    use Jido.Agent,
      name: "zoi_schema_agent",
      schema:
        Zoi.object(%{
          status: Zoi.atom() |> Zoi.default(:idle),
          count: Zoi.integer() |> Zoi.default(0)
        })

    def signal_routes(_ctx), do: []
  end

  defmodule WithCustomStrategy do
    @moduledoc "Agent with a strategy that emits directives from init/2"
    use Jido.Agent,
      name: "with_custom_strategy_agent",
      strategy: JidoTest.TestAgents.InitDirectiveStrategy,
      schema: [
        value: [type: :integer, default: 0]
      ]

    def signal_routes(_ctx), do: []
  end

  defmodule TestPluginWithRoutes do
    @moduledoc false
    use Jido.Plugin,
      name: "test_routes_plugin",
      state_key: :test_routes,
      actions: [JidoTest.PluginTestAction],
      signal_routes: [
        {"post", JidoTest.PluginTestAction},
        {"list", JidoTest.PluginTestAction}
      ]
  end

  defmodule TestPluginWithPriority do
    @moduledoc false
    use Jido.Plugin,
      name: "priority_plugin",
      state_key: :priority,
      actions: [JidoTest.PluginTestAction],
      signal_routes: [
        {"action", JidoTest.PluginTestAction, priority: 5}
      ]
  end

  defmodule AgentWithPluginRoutes do
    @moduledoc false
    use Jido.Agent,
      name: "agent_with_plugin_routes",
      plugins: [JidoTest.TestAgents.TestPluginWithRoutes]

    def signal_routes(_ctx), do: []
  end

  defmodule AgentWithMultiInstancePlugins do
    @moduledoc false
    use Jido.Agent,
      name: "agent_multi_instance",
      plugins: [
        {JidoTest.TestAgents.TestPluginWithRoutes, as: :support},
        {JidoTest.TestAgents.TestPluginWithRoutes, as: :sales}
      ]

    def signal_routes(_ctx), do: []
  end
end
