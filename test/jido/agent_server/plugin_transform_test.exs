defmodule JidoTest.AgentServer.PluginTransformTest do
  use JidoTest.Case, async: true

  alias Jido.Signal

  # Test action
  defmodule SetValueAction do
    @moduledoc false
    use Jido.Action,
      name: "set_value",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(42)})

    alias Jido.Agent.StateOp

    def run(%{value: value}, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:value], value: value}}
    end
  end

  # Plugin with default transform (identity)
  defmodule DefaultTransformPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "default_transform",
      state_key: :default_transform,
      actions: [JidoTest.AgentServer.PluginTransformTest.SetValueAction],
      signal_patterns: ["value.*"]
  end

  # Plugin that wraps agent with metadata
  defmodule MetadataTransformPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "metadata_transform",
      state_key: :metadata_transform,
      actions: [JidoTest.AgentServer.PluginTransformTest.SetValueAction],
      signal_patterns: ["value.*"]

    @impl Jido.Plugin
    def transform_result(_action, agent, _context) do
      new_state = Map.put(agent.state, :transformed_by, __MODULE__)
      %{agent | state: new_state}
    end
  end

  # Plugin that adds timestamp
  defmodule TimestampTransformPlugin do
    @moduledoc false
    use Jido.Plugin,
      name: "timestamp_transform",
      state_key: :timestamp_transform,
      actions: [JidoTest.AgentServer.PluginTransformTest.SetValueAction],
      signal_patterns: ["value.*"]

    @impl Jido.Plugin
    def transform_result(_action, agent, _context) do
      new_state = Map.put(agent.state, :transformed_at, DateTime.utc_now())
      %{agent | state: new_state}
    end
  end

  # Agent with default transform
  defmodule DefaultTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "default_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginTransformTest.DefaultTransformPlugin]

    def signal_routes(_ctx) do
      [{"value.set", JidoTest.AgentServer.PluginTransformTest.SetValueAction}]
    end
  end

  # Agent with metadata transform
  defmodule MetadataTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "metadata_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      plugins: [JidoTest.AgentServer.PluginTransformTest.MetadataTransformPlugin]

    def signal_routes(_ctx) do
      [{"value.set", JidoTest.AgentServer.PluginTransformTest.SetValueAction}]
    end
  end

  # Agent with multiple transform plugins (chained)
  defmodule ChainedTransformAgent do
    @moduledoc false
    use Jido.Agent,
      name: "chained_transform_agent",
      schema: [value: [type: :integer, default: 0]],
      plugins: [
        JidoTest.AgentServer.PluginTransformTest.MetadataTransformPlugin,
        JidoTest.AgentServer.PluginTransformTest.TimestampTransformPlugin
      ]

    def signal_routes(_ctx) do
      [{"value.set", JidoTest.AgentServer.PluginTransformTest.SetValueAction}]
    end
  end

  describe "transform_result/3 with default implementation" do
    test "agent returned unchanged when plugin uses default transform", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: DefaultTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 100}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 100
      refute Map.has_key?(agent.state, :transformed_by)
    end
  end

  describe "transform_result/3 with custom implementation" do
    test "plugin can add metadata to returned agent", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 50}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 50

      assert agent.state[:transformed_by] ==
               JidoTest.AgentServer.PluginTransformTest.MetadataTransformPlugin
    end

    test "transform only affects call path, not internal state", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 75}, source: "/test")
      {:ok, returned_agent} = Jido.AgentServer.call(pid, signal)

      # Returned agent has transform applied
      assert returned_agent.state[:transformed_by] ==
               JidoTest.AgentServer.PluginTransformTest.MetadataTransformPlugin

      # Internal state does NOT have transform (transforms are for caller view only)
      {:ok, state} = Jido.AgentServer.state(pid)
      refute Map.has_key?(state.agent.state, :transformed_by)
      assert state.agent.state[:value] == 75
    end
  end

  describe "transform_result/3 with multiple plugins" do
    test "transforms are chained across plugins", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChainedTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 25}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert agent.state[:value] == 25
      # Both transforms should have run
      assert agent.state[:transformed_by] ==
               JidoTest.AgentServer.PluginTransformTest.MetadataTransformPlugin

      assert agent.state[:transformed_at] != nil
    end
  end

  describe "transform_result/3 with cast (no transform)" do
    test "cast path does not apply transforms (fire and forget)", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: MetadataTransformAgent, jido: jido)

      signal = Signal.new!("value.set", %{value: 33}, source: "/test")
      :ok = Jido.AgentServer.cast(pid, signal)

      state = eventually_state(pid, fn state -> state.agent.state[:value] == 33 end)
      # No transform applied because it was cast, not call
      refute Map.has_key?(state.agent.state, :transformed_by)
    end
  end
end
