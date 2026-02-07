defmodule JidoTest.AgentServer.PluginSignalHooksTest do
  use JidoTest.Case, async: true

  alias Jido.Signal

  # Test action that increments a counter
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

  # Override action
  defmodule OverrideAction do
    @moduledoc false
    use Jido.Action,
      name: "override_action",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:overridden], value: true}}
    end
  end

  # Plugin with default handle_signal (continues to router)
  defmodule DefaultHandleSignalPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "default_handle_signal",
      state_key: :default_hs,
      actions: [JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction]
  end

  # Plugin that overrides routing for specific signals
  defmodule OverridePlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "override_plugin",
      state_key: :override,
      actions: [
        JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction,
        JidoTest.AgentServer.PluginSignalHooksTest.OverrideAction
      ]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "counter.override" do
        {:ok, {:override, JidoTest.AgentServer.PluginSignalHooksTest.OverrideAction}}
      else
        {:ok, :continue}
      end
    end
  end

  # Plugin that returns error for specific signals
  defmodule ErrorPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "error_plugin",
      state_key: :error_plugin,
      actions: [JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction]

    @impl Jido.Plugin
    def handle_signal(signal, _context) do
      if signal.type == "counter.error" do
        {:error, :plugin_rejected_signal}
      else
        {:ok, :continue}
      end
    end
  end

  # Agent with default handle_signal plugin
  defmodule DefaultHandleSignalAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_handle_signal_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalHooksTest.DefaultHandleSignalPlugin]

    def signal_routes(_ctx) do
      [{"counter.increment", JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction}]
    end
  end

  # Agent with override plugin
  defmodule OverrideAgent do
    @moduledoc false
    use Jido.Agent,
      name: "override_agent",
      schema: [
        counter: [type: :integer, default: 0],
        overridden: [type: :boolean, default: false]
      ],
      plugins: [JidoTest.AgentServer.PluginSignalHooksTest.OverridePlugin]

    def signal_routes(_ctx) do
      [
        {"counter.increment", JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction},
        {"counter.override", JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction}
      ]
    end
  end

  # Agent with error plugin
  defmodule ErrorAgent do
    @moduledoc false
    use Jido.Agent,
      name: "error_agent",
      schema: [counter: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginSignalHooksTest.ErrorPlugin]

    def signal_routes(_ctx) do
      [
        {"counter.increment", JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction},
        {"counter.error", JidoTest.AgentServer.PluginSignalHooksTest.IncrementAction}
      ]
    end
  end

  describe "handle_signal/2 with default implementation" do
    test "signals route normally when plugin uses default handle_signal", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DefaultHandleSignalAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 5}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 5
    end
  end

  describe "handle_signal/2 with override" do
    test "plugin can override routing by returning {:ok, {:override, action}}", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: OverrideAgent, jido: jido)

      # This would normally route to IncrementAction, but plugin overrides it
      signal = Signal.new!("counter.override", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Override action sets :overridden to true instead of incrementing
      assert agent.state[:overridden] == true
      # Not incremented
      assert agent.state[:counter] == 0
    end

    test "plugin continues to normal routing when not overriding", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: OverrideAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 10}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 10
      assert agent.state[:overridden] == false
    end
  end

  describe "handle_signal/2 with error" do
    test "plugin can abort signal processing by returning error", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ErrorAgent, jido: jido)

      signal = Signal.new!("counter.error", %{}, source: "/test")
      result = Jido.AgentServer.call(pid, signal)

      # Should return error
      assert {:error, error} = result
      assert error.message == "Plugin handle_signal failed"

      # Agent state should be unchanged
      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.agent.state[:counter] == 0
    end

    test "non-error signals still process normally", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ErrorAgent, jido: jido)

      signal = Signal.new!("counter.increment", %{amount: 3}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:counter] == 3
    end
  end
end
