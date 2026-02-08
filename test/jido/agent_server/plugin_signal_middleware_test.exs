defmodule JidoTest.AgentServer.PluginSignalMiddlewareTest do
  use JidoTest.Case, async: true

  alias Jido.Signal

  # --- Shared Actions ---

  defmodule IncrementAction do
    @moduledoc false
    use Jido.Action,
      name: "increment",
      schema: Zoi.object(%{amount: Zoi.integer() |> Zoi.default(1)})

    alias Jido.Agent.StateOp

    def run(%{amount: amount}, %{state: state}) do
      current = get_in(state, [:counter]) || 0
      {:ok, %{}, %StateOp.SetPath{path: [:counter], value: current + amount}}
    end
  end

  defmodule MarkAction do
    @moduledoc false
    use Jido.Action,
      name: "mark",
      schema: Zoi.object(%{marker: Zoi.string() |> Zoi.default("marked")})

    alias Jido.Agent.StateOp

    def run(%{marker: marker}, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:marker], value: marker}}
    end
  end

  # =========================================================================
  # Gap 2: Signal Transformation
  # =========================================================================

  defmodule SignalRewritePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "signal_rewrite",
      state_key: :signal_rewrite,
      actions: [
        JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction
      ]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "counter.double" do
        new_data = Map.put(signal.data, :amount, (signal.data[:amount] || 1) * 2)
        new_signal = %{signal | data: new_data}
        {:ok, {:continue, new_signal}}
      else
        {:ok, :continue}
      end
    end
  end

  defmodule SignalRewriteAgent do
    @moduledoc false
    use Jido.Agent,
      name: "signal_rewrite_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.SignalRewritePlugin]

    def signal_routes(_ctx) do
      [
        {"counter.double", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  defmodule OverrideWithSignalPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "override_with_signal",
      state_key: :override_ws,
      actions: [
        JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction,
        JidoTest.AgentServer.PluginSignalMiddlewareTest.MarkAction
      ]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "counter.special" do
        new_signal = %{signal | data: Map.put(signal.data, :marker, "special_override")}

        {:ok,
         {:override,
          {JidoTest.AgentServer.PluginSignalMiddlewareTest.MarkAction,
           %{marker: "special_override"}}, new_signal}}
      else
        {:ok, :continue}
      end
    end
  end

  defmodule OverrideWithSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "override_with_signal_agent",
      schema: [
        counter: [type: :integer, default: 0],
        marker: [type: :string, default: nil]
      ],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.OverrideWithSignalPlugin]

    def signal_routes(_ctx) do
      [
        {"counter.special", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  defmodule AddPrefixPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "add_prefix",
      state_key: :add_prefix,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      new_data = Map.put(signal.data, :prefix_applied, true)
      {:ok, {:continue, %{signal | data: new_data}}}
    end
  end

  defmodule MultiplyAmountPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "multiply_amount",
      state_key: :multiply_amount,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.data[:prefix_applied] do
        new_data = Map.put(signal.data, :amount, (signal.data[:amount] || 1) * 3)
        {:ok, {:continue, %{signal | data: new_data}}}
      else
        {:ok, :continue}
      end
    end
  end

  defmodule ChainedSignalRewriteAgent do
    @moduledoc false
    use Jido.Agent,
      name: "chained_signal_rewrite_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [
        JidoTest.AgentServer.PluginSignalMiddlewareTest.AddPrefixPlugin,
        JidoTest.AgentServer.PluginSignalMiddlewareTest.MultiplyAmountPlugin
      ]

    def signal_routes(_ctx) do
      [{"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}]
    end
  end

  describe "Gap 2: handle_signal/2 signal transformation" do
    test "plugin can modify signal data with {:continue, new_signal}", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SignalRewriteAgent, jido: jido)

      signal = Signal.new!("counter.double", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 10
    end

    test "unmatched signals pass through unmodified", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SignalRewriteAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 7}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 7
    end

    test "plugin can override with modified signal", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: OverrideWithSignalAgent, jido: jido)

      signal = Signal.new!("counter.special", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:marker] == "special_override"
      assert agent.state[:counter] == 0
    end

    test "signal modifications chain through multiple plugins", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChainedSignalRewriteAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 4}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 12
    end
  end

  # =========================================================================
  # Gap 4: Signal Pattern Filtering
  # =========================================================================

  defmodule RejectAllPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "reject_all",
      state_key: :reject_all,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction],
      signal_patterns: ["counter.*"]

    @impl Jido.Plugin
    def handle_signal(_signal, _context) do
      {:error, :rejected_by_plugin}
    end
  end

  defmodule FilteredRejectAgent do
    @moduledoc false
    use Jido.Agent,
      name: "filtered_reject_agent",
      schema: [
        counter: [type: :integer, default: 0],
        other: [type: :integer, default: 0]
      ],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.RejectAllPlugin]

    def signal_routes(_ctx) do
      [
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"other.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  defmodule GlobalMiddlewarePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "global_middleware",
      state_key: :global_mw,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction],
      signal_patterns: []

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      new_data = Map.put(signal.data, :amount, (signal.data[:amount] || 1) + 100)
      {:ok, {:continue, %{signal | data: new_data}}}
    end
  end

  defmodule GlobalMiddlewareAgent do
    @moduledoc false
    use Jido.Agent,
      name: "global_middleware_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.GlobalMiddlewarePlugin]

    def signal_routes(_ctx) do
      [
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"other.action", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  defmodule WildcardPatternPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "wildcard_pattern",
      state_key: :wildcard,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction],
      signal_patterns: ["api.*.create"]

    @impl Jido.Plugin
    def handle_signal(_signal, _context) do
      {:error, :blocked_by_wildcard}
    end
  end

  defmodule WildcardPatternAgent do
    @moduledoc false
    use Jido.Agent,
      name: "wildcard_pattern_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.WildcardPatternPlugin]

    def signal_routes(_ctx) do
      [
        {"api.user.create", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"api.user.delete", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"other.action", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  describe "Gap 4: signal pattern filtering" do
    test "plugin with patterns only receives matching signals", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: FilteredRejectAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 5}, source: "/test")
      assert {:error, _} = Jido.AgentServer.call(pid, signal)
    end

    test "plugin with patterns does not receive non-matching signals", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: FilteredRejectAgent, jido: jido)

      signal = Signal.new!("other.increment", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)
      assert agent.state[:counter] == 5
    end

    test "plugin with empty patterns receives all signals", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: GlobalMiddlewareAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)
      assert agent.state[:counter] == 101

      signal2 = Signal.new!("other.action", %{amount: 1}, source: "/test")
      {:ok, agent2} = Jido.AgentServer.call(pid, signal2)
      assert agent2.state[:counter] == 202
    end

    test "wildcard segment pattern matches correctly", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: WildcardPatternAgent, jido: jido)

      signal = Signal.new!("api.user.create", %{amount: 1}, source: "/test")
      assert {:error, _} = Jido.AgentServer.call(pid, signal)
    end

    test "wildcard segment pattern does not match different suffix", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: WildcardPatternAgent, jido: jido)

      signal = Signal.new!("api.user.delete", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)
      assert agent.state[:counter] == 1
    end

    test "unrelated signals skip patterned plugins entirely", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: WildcardPatternAgent, jido: jido)

      signal = Signal.new!("other.action", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)
      assert agent.state[:counter] == 5
    end
  end

  # =========================================================================
  # Gap 5: Resolved Action in transform_result
  # =========================================================================

  defmodule ActionAwareTransformPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "action_aware_transform",
      state_key: :action_aware,
      actions: [
        JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction,
        JidoTest.AgentServer.PluginSignalMiddlewareTest.MarkAction
      ]

    @impl Jido.Plugin
    def transform_result(action, agent, _context) do
      action_name =
        if is_atom(action) and not is_nil(action) do
          action |> Module.split() |> List.last()
        else
          "unknown"
        end

      new_state = Map.put(agent.state, :last_action, action_name)
      %{agent | state: new_state}
    end
  end

  defmodule ActionAwareTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "action_aware_transform_agent",
      schema: [
        counter: [type: :integer, default: 0],
        marker: [type: :string, default: nil]
      ],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.ActionAwareTransformPlugin]

    def signal_routes(_ctx) do
      [
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"marker.set", JidoTest.AgentServer.PluginSignalMiddlewareTest.MarkAction}
      ]
    end
  end

  describe "Gap 5: resolved action in transform_result" do
    test "transform_result receives resolved action module", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ActionAwareTransformAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 3}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 3
      assert agent.state[:last_action] == "IncrementAction"
    end

    test "transform_result distinguishes different action modules", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ActionAwareTransformAgent, jido: jido)

      signal = Signal.new!("marker.set", %{marker: "hello"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:marker] == "hello"
      assert agent.state[:last_action] == "MarkAction"
    end

    test "transform only affects call path, not internal state", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ActionAwareTransformAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 1}, source: "/test")
      {:ok, returned_agent} = Jido.AgentServer.call(pid, signal)

      assert returned_agent.state[:last_action] == "IncrementAction"

      {:ok, state} = Jido.AgentServer.state(pid)
      refute Map.has_key?(state.agent.state, :last_action)
    end
  end

  # =========================================================================
  # Gap 6: Exception Safety
  # =========================================================================

  defmodule CrashingHandleSignalPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "crashing_handle_signal",
      state_key: :crashing_hs,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "crash.me" do
        raise "Intentional plugin crash!"
      else
        {:ok, :continue}
      end
    end
  end

  defmodule CrashingHandleSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "crashing_hs_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.CrashingHandleSignalPlugin]

    def signal_routes(_ctx) do
      [
        {"crash.me", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  defmodule CrashingTransformPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "crashing_transform",
      state_key: :crashing_tr,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def transform_result(_action, _agent, _context) do
      raise "Transform crash!"
    end
  end

  defmodule CrashingTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "crashing_transform_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.CrashingTransformPlugin]

    def signal_routes(_ctx) do
      [{"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}]
    end
  end

  defmodule SlowHandleSignalPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "slow_handle_signal",
      state_key: :slow_hs,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(_signal, _context) do
      Process.sleep(1_200)
      {:ok, :continue}
    end
  end

  defmodule SlowHandleSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "slow_handle_signal_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.SlowHandleSignalPlugin]

    def signal_routes(_ctx) do
      [{"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}]
    end
  end

  describe "Gap 6: exception safety" do
    @tag capture_log: true
    test "handle_signal crash returns error without crashing server", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: CrashingHandleSignalAgent, jido: jido)

      signal = Signal.new!("crash.me", %{}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert error.message == "Plugin handle_signal crashed"

      assert Process.alive?(pid)
    end

    @tag capture_log: true
    test "server continues normally after handle_signal crash", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: CrashingHandleSignalAgent, jido: jido)

      crash_signal = Signal.new!("crash.me", %{}, source: "/test")
      assert {:error, _} = Jido.AgentServer.call(pid, crash_signal)

      signal = Signal.new!("counter.increment", %{amount: 42}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 42
    end

    @tag capture_log: true
    test "transform_result crash does not crash server, returns agent unchanged", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: CrashingTransformAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 10}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 10
      assert Process.alive?(pid)
    end

    @tag capture_log: true
    test "handle_signal timeout returns structured timeout error", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: SlowHandleSignalAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 2}, source: "/test")
      assert {:error, error} = Jido.AgentServer.call(pid, signal)
      assert error.message == "Plugin handle_signal timed out"
      assert Process.alive?(pid)
    end
  end

  # =========================================================================
  # Gap 7: Plugin Instance in Context
  # =========================================================================

  defmodule InstanceContextPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "instance_context",
      state_key: :instance_ctx,
      actions: [JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(signal, context) do
      if signal.type == "check.context" do
        has_instance = Map.has_key?(context, :plugin_instance)

        if has_instance do
          instance = context.plugin_instance

          new_data =
            Map.merge(signal.data, %{
              has_instance: true,
              instance_module: instance.module,
              instance_state_key: instance.state_key
            })

          {:ok, {:continue, %{signal | data: new_data}}}
        else
          {:ok, :continue}
        end
      else
        {:ok, :continue}
      end
    end

    @impl Jido.Plugin
    def transform_result(_action, agent, context) do
      has_instance = Map.has_key?(context, :plugin_instance)
      new_state = Map.put(agent.state, :transform_has_instance, has_instance)
      %{agent | state: new_state}
    end
  end

  defmodule InstanceContextAgent do
    @moduledoc false
    use Jido.Agent,
      name: "instance_context_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalMiddlewareTest.InstanceContextPlugin]

    def signal_routes(_ctx) do
      [
        {"check.context", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction},
        {"counter.increment", JidoTest.AgentServer.PluginSignalMiddlewareTest.IncrementAction}
      ]
    end
  end

  describe "Gap 7: plugin instance in context" do
    test "handle_signal context includes plugin_instance", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: InstanceContextAgent, jido: jido)

      signal = Signal.new!("check.context", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 1
    end

    test "transform_result context includes plugin_instance", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: InstanceContextAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 1}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:transform_has_instance] == true
    end
  end
end
