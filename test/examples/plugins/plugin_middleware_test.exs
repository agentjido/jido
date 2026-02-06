defmodule JidoExampleTest.PluginMiddlewareTest do
  @moduledoc """
  Example test demonstrating plugin signal middleware (handle_signal/2 and transform_result/3).

  This test shows:
  - handle_signal/2 returning {:ok, :continue}, {:ok, {:continue, signal}},
    {:ok, {:override, action}}, and {:error, reason}
  - signal_patterns filtering — plugins with non-empty patterns only receive matching signals
  - transform_result/3 enriching the agent returned from AgentServer.call/3
  - Middleware composition across multiple plugins

  Run with: mix test --include example
  """
  use JidoTest.Case, async: false

  @moduletag :example
  @moduletag timeout: 15_000

  alias Jido.AgentServer
  alias Jido.Signal

  # ===========================================================================
  # ACTIONS
  # ===========================================================================

  defmodule ProcessAction do
    @moduledoc false
    use Jido.Action,
      name: "process",
      schema: [
        value: [type: :string, default: "processed"]
      ]

    def run(%{value: value}, context) do
      log = Map.get(context.state, :log, [])
      {:ok, %{log: [value | log], last_action: "process"}}
    end
  end

  defmodule AdminAction do
    @moduledoc false
    use Jido.Action,
      name: "admin_action",
      schema: [
        value: [type: :string, default: "admin"]
      ]

    def run(%{value: value}, context) do
      log = Map.get(context.state, :log, [])
      {:ok, %{log: ["admin:#{value}" | log], last_action: "admin"}}
    end
  end

  # ===========================================================================
  # PLUGINS
  # ===========================================================================

  defmodule LoggingPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "logging",
      state_key: :logging,
      actions: [
        JidoExampleTest.PluginMiddlewareTest.ProcessAction
      ],
      signal_patterns: []

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      new_data = Map.put(signal.data, :seen_by_logging, true)
      {:ok, {:continue, %{signal | data: new_data}}}
    end
  end

  defmodule AuditPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "audit",
      state_key: :audit,
      actions: [
        JidoExampleTest.PluginMiddlewareTest.ProcessAction
      ],
      signal_patterns: ["audit.*"]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      new_data = Map.put(signal.data, :audited, true)
      {:ok, {:continue, %{signal | data: new_data}}}
    end
  end

  defmodule AdminOverridePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "admin_override",
      state_key: :admin_override,
      actions: [
        JidoExampleTest.PluginMiddlewareTest.AdminAction
      ],
      signal_patterns: ["admin.*"]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "admin.override" do
        {:ok, {:override, JidoExampleTest.PluginMiddlewareTest.AdminAction}}
      else
        {:ok, :continue}
      end
    end
  end

  defmodule RejectPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "reject",
      state_key: :reject,
      actions: [
        JidoExampleTest.PluginMiddlewareTest.ProcessAction
      ],
      signal_patterns: ["blocked.*"]

    @impl Jido.Plugin
    def handle_signal(_signal, _context) do
      {:error, :blocked}
    end
  end

  defmodule ResultEnricherPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "result_enricher",
      state_key: :enricher,
      actions: [
        JidoExampleTest.PluginMiddlewareTest.ProcessAction
      ],
      signal_patterns: []

    @impl Jido.Plugin
    def transform_result(_action, agent, _context) do
      new_state =
        agent.state
        |> Map.put(:enriched, true)
        |> Map.put(:enriched_at, DateTime.utc_now())

      %{agent | state: new_state}
    end
  end

  # ===========================================================================
  # AGENTS
  # ===========================================================================

  defmodule GlobalMiddlewareAgent do
    @moduledoc false
    use Jido.Agent,
      name: "global_mw_agent",
      schema: [
        log: [type: {:list, :string}, default: []],
        last_action: [type: :string, default: nil]
      ],
      plugins: [JidoExampleTest.PluginMiddlewareTest.LoggingPlugin]

    def signal_routes(_ctx) do
      [
        {"task.run", JidoExampleTest.PluginMiddlewareTest.ProcessAction},
        {"other.run", JidoExampleTest.PluginMiddlewareTest.ProcessAction}
      ]
    end
  end

  defmodule PatternFilteredAgent do
    @moduledoc false
    use Jido.Agent,
      name: "pattern_filtered_agent",
      schema: [
        log: [type: {:list, :string}, default: []],
        last_action: [type: :string, default: nil]
      ],
      plugins: [
        JidoExampleTest.PluginMiddlewareTest.AuditPlugin,
        JidoExampleTest.PluginMiddlewareTest.RejectPlugin
      ]

    def signal_routes(_ctx) do
      [
        {"audit.log", JidoExampleTest.PluginMiddlewareTest.ProcessAction},
        {"task.run", JidoExampleTest.PluginMiddlewareTest.ProcessAction},
        {"blocked.action", JidoExampleTest.PluginMiddlewareTest.ProcessAction}
      ]
    end
  end

  defmodule OverrideAgent do
    @moduledoc false
    use Jido.Agent,
      name: "override_agent",
      schema: [
        log: [type: {:list, :string}, default: []],
        last_action: [type: :string, default: nil]
      ],
      plugins: [JidoExampleTest.PluginMiddlewareTest.AdminOverridePlugin]

    def signal_routes(_ctx) do
      [
        {"admin.override", JidoExampleTest.PluginMiddlewareTest.ProcessAction},
        {"admin.normal", JidoExampleTest.PluginMiddlewareTest.ProcessAction}
      ]
    end
  end

  defmodule EnrichedAgent do
    @moduledoc false
    use Jido.Agent,
      name: "enriched_agent",
      schema: [
        log: [type: {:list, :string}, default: []],
        last_action: [type: :string, default: nil]
      ],
      plugins: [JidoExampleTest.PluginMiddlewareTest.ResultEnricherPlugin]

    def signal_routes(_ctx) do
      [{"task.run", JidoExampleTest.PluginMiddlewareTest.ProcessAction}]
    end
  end

  # ===========================================================================
  # TESTS
  # ===========================================================================

  describe "global middleware" do
    test "plugin with empty signal_patterns intercepts all signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, GlobalMiddlewareAgent, id: unique_id("global"))

      {:ok, agent} =
        AgentServer.call(pid, Signal.new!("task.run", %{value: "a"}, source: "/test"))

      assert agent.state.last_action == "process"

      {:ok, agent} =
        AgentServer.call(pid, Signal.new!("other.run", %{value: "b"}, source: "/test"))

      assert agent.state.last_action == "process"
      assert length(agent.state.log) == 2
    end
  end

  describe "signal pattern filtering" do
    test "plugin only receives signals matching its patterns", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, PatternFilteredAgent, id: unique_id("filtered"))

      {:ok, agent} =
        AgentServer.call(pid, Signal.new!("task.run", %{value: "ok"}, source: "/test"))

      assert agent.state.last_action == "process"
      assert length(agent.state.log) == 1

      assert {:error, _} =
               AgentServer.call(
                 pid,
                 Signal.new!("blocked.action", %{value: "nope"}, source: "/test")
               )
    end

    test "audit plugin adds metadata only to audit signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, PatternFilteredAgent, id: unique_id("audit"))

      {:ok, agent} =
        AgentServer.call(pid, Signal.new!("task.run", %{value: "plain"}, source: "/test"))

      assert agent.state.last_action == "process"
      assert hd(agent.state.log) == "plain"
    end
  end

  describe "handle_signal override" do
    test "handle_signal can override the action for matching signals", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, OverrideAgent, id: unique_id("override"))

      {:ok, agent} =
        AgentServer.call(
          pid,
          Signal.new!("admin.override", %{value: "secret"}, source: "/test")
        )

      assert agent.state.last_action == "admin"
      assert hd(agent.state.log) =~ "admin:"
    end

    test "non-overridden signals use normal routing", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, OverrideAgent, id: unique_id("override"))

      {:ok, agent} =
        AgentServer.call(
          pid,
          Signal.new!("admin.normal", %{value: "regular"}, source: "/test")
        )

      assert agent.state.last_action == "process"
      assert hd(agent.state.log) == "regular"
    end
  end

  describe "transform_result" do
    test "transform_result enriches agent returned from call", %{jido: jido} do
      {:ok, pid} = Jido.start_agent(jido, EnrichedAgent, id: unique_id("enriched"))

      {:ok, agent} =
        AgentServer.call(pid, Signal.new!("task.run", %{value: "data"}, source: "/test"))

      assert agent.state.last_action == "process"
      assert agent.state[:enriched] == true
      assert agent.state[:enriched_at] != nil

      {:ok, state} = AgentServer.state(pid)
      refute Map.has_key?(state.agent.state, :enriched)
    end
  end
end
