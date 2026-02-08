defmodule JidoTest.PluginLifecycleTest do
  @moduledoc """
  End-to-end integration tests for Jido Plugin lifecycle.

  Tests all 4 callbacks working together:
  - mount/2 - Pure initialization during Agent.new/1
  - handle_signal/2 - Pre-routing hook in AgentServer
  - transform_result/3 - Post-processing on call path
  - child_spec/1 - Child process management
  """
  use JidoTest.Case, async: true

  alias Jido.Signal

  # =============================================================================
  # Test Actions
  # =============================================================================

  defmodule AddMessageAction do
    @moduledoc false
    use Jido.Action,
      name: "add_message",
      schema:
        Zoi.object(%{
          role: Zoi.string(),
          content: Zoi.string()
        })

    alias Jido.Agent.StateOp

    def run(%{role: role, content: content}, %{state: state}) do
      messages = get_in(state, [:chat, :messages]) || []
      new_message = %{role: role, content: content, timestamp: DateTime.utc_now()}
      {:ok, %{}, %StateOp.SetPath{path: [:chat, :messages], value: messages ++ [new_message]}}
    end
  end

  defmodule ClearMessagesAction do
    @moduledoc false
    use Jido.Action,
      name: "clear_messages",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, _context) do
      {:ok, %{}, %StateOp.SetPath{path: [:chat, :messages], value: []}}
    end
  end

  defmodule GetStatsAction do
    @moduledoc false
    use Jido.Action,
      name: "get_stats",
      schema: []

    alias Jido.Agent.StateOp

    def run(_params, %{state: state}) do
      messages = get_in(state, [:chat, :messages]) || []
      message_count = length(messages)

      {:ok, %{},
       %StateOp.SetPath{
         path: [:chat, :last_stats],
         value: %{
           message_count: message_count,
           computed_at: DateTime.utc_now()
         }
       }}
    end
  end

  # =============================================================================
  # Full-Featured Chat Plugin
  # =============================================================================

  defmodule ChatPlugin do
    @moduledoc """
    A comprehensive chat plugin demonstrating all callbacks.

    - mount/2: Initializes conversation metadata
    - handle_signal/2: Rate limits and logs signals
    - transform_result/3: Adds response metadata
    - child_spec/1: Starts a message counter worker
    """
    use Jido.Plugin,
      name: "chat_plugin",
      state_key: :chat,
      actions: [
        JidoTest.PluginLifecycleTest.AddMessageAction,
        JidoTest.PluginLifecycleTest.ClearMessagesAction,
        JidoTest.PluginLifecycleTest.GetStatsAction
      ],
      schema:
        Zoi.object(%{
          messages: Zoi.list(Zoi.any()) |> Zoi.default([]),
          model: Zoi.string() |> Zoi.default("gpt-4"),
          last_stats: Zoi.any() |> Zoi.optional()
        }),
      signal_patterns: ["chat.*"]

    @impl Jido.Plugin
    def mount(_agent, config) do
      {:ok,
       %{
         initialized_at: DateTime.utc_now(),
         session_id: config[:session_id] || generate_session_id(),
         config: config
       }}
    end

    @impl Jido.Plugin
    def signal_routes(_config) do
      [
        {"chat.message", JidoTest.PluginLifecycleTest.AddMessageAction},
        {"chat.clear", JidoTest.PluginLifecycleTest.ClearMessagesAction},
        {"chat.stats", JidoTest.PluginLifecycleTest.GetStatsAction}
      ]
    end

    @impl Jido.Plugin
    def handle_signal(signal, context) do
      # Log all signals
      plugin_state = Map.get(context.agent.state, :chat, %{})
      message_count = length(plugin_state[:messages] || [])

      # Rate limit: reject if too many messages
      max_messages = context.config[:max_messages] || 100

      if message_count >= max_messages and signal.type == "chat.message" do
        {:error, :rate_limit_exceeded}
      else
        {:ok, :continue}
      end
    end

    @impl Jido.Plugin
    def transform_result(_action, agent, _context) do
      # Add response metadata to the returned agent
      chat_state = Map.get(agent.state, :chat, %{})
      message_count = length(chat_state[:messages] || [])

      metadata = %{
        plugin: __MODULE__,
        session_id: chat_state[:session_id],
        message_count: message_count,
        processed_at: DateTime.utc_now()
      }

      new_state = Map.put(agent.state, :__chat_metadata__, metadata)
      %{agent | state: new_state}
    end

    @impl Jido.Plugin
    def child_spec(config) do
      # Start a simple counter agent to track total messages processed
      %{
        id: {__MODULE__, :counter},
        start:
          {Agent, :start_link,
           [
             fn ->
               %{total_processed: 0, started_at: DateTime.utc_now(), config: config}
             end
           ]}
      }
    end

    defp generate_session_id do
      :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    end
  end

  # =============================================================================
  # Agents
  # =============================================================================

  defmodule ChatAgent do
    @moduledoc false
    use Jido.Agent,
      name: "chat_agent",
      plugins: [JidoTest.PluginLifecycleTest.ChatPlugin]
  end

  defmodule ConfiguredChatAgent do
    @moduledoc false
    use Jido.Agent,
      name: "configured_chat_agent",
      plugins: [
        {JidoTest.PluginLifecycleTest.ChatPlugin, %{session_id: "test-session", max_messages: 5}}
      ]
  end

  # =============================================================================
  # Tests: mount/2 Lifecycle
  # =============================================================================

  describe "mount/2 lifecycle" do
    test "mount initializes plugin state with schema defaults and custom fields" do
      agent = ChatAgent.new()

      # Schema defaults
      assert agent.state[:chat][:messages] == []
      assert agent.state[:chat][:model] == "gpt-4"

      # Mount additions
      assert agent.state[:chat][:initialized_at] != nil
      assert agent.state[:chat][:session_id] != nil
    end

    test "mount receives plugin config" do
      agent = ConfiguredChatAgent.new()

      assert agent.state[:chat][:session_id] == "test-session"
      assert agent.state[:chat][:config][:max_messages] == 5
    end
  end

  # =============================================================================
  # Tests: handle_signal/2 Lifecycle
  # =============================================================================

  describe "handle_signal/2 lifecycle" do
    test "signals process normally when under rate limit", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ConfiguredChatAgent, jido: jido)

      signal = Signal.new!("chat.message", %{role: "user", content: "Hello"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      assert length(agent.state[:chat][:messages]) == 1

      GenServer.stop(pid)
    end

    test "handle_signal can reject signals", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ConfiguredChatAgent, jido: jido)

      # Send max_messages (5) messages
      for i <- 1..5 do
        signal =
          Signal.new!("chat.message", %{role: "user", content: "Message #{i}"}, source: "/test")

        {:ok, _} = Jido.AgentServer.call(pid, signal)
      end

      # 6th message should be rate limited
      signal =
        Signal.new!("chat.message", %{role: "user", content: "One too many"}, source: "/test")

      result = Jido.AgentServer.call(pid, signal)

      assert {:error, _} = result

      # Verify we still have only 5 messages
      {:ok, state} = Jido.AgentServer.state(pid)
      assert length(state.agent.state[:chat][:messages]) == 5

      GenServer.stop(pid)
    end
  end

  defp await_children(pid, expected_count) do
    eventually_state(pid, fn state -> map_size(state.children) == expected_count end)
    {:ok, state} = Jido.AgentServer.state(pid)
    state
  end

  # =============================================================================
  # Tests: transform_result/3 Lifecycle
  # =============================================================================

  describe "transform_result/3 lifecycle" do
    test "transform adds metadata to returned agent", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChatAgent, jido: jido)

      signal = Signal.new!("chat.message", %{role: "user", content: "Test"}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Transform should have added metadata
      metadata = agent.state[:__chat_metadata__]
      assert metadata != nil
      assert metadata[:plugin] == JidoTest.PluginLifecycleTest.ChatPlugin
      assert metadata[:message_count] == 1
      assert metadata[:processed_at] != nil

      GenServer.stop(pid)
    end

    test "transform does not affect internal server state", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChatAgent, jido: jido)

      signal = Signal.new!("chat.message", %{role: "user", content: "Test"}, source: "/test")
      {:ok, _returned_agent} = Jido.AgentServer.call(pid, signal)

      # Internal state should NOT have the transform metadata
      {:ok, state} = Jido.AgentServer.state(pid)
      refute Map.has_key?(state.agent.state, :__chat_metadata__)

      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # Tests: child_spec/1 Lifecycle
  # =============================================================================

  describe "child_spec/1 lifecycle" do
    test "plugin child is started during AgentServer init", %{jido: jido} do
      {:ok, pid} = Jido.AgentServer.start_link(agent: ChatAgent, jido: jido)
      state = await_children(pid, 1)

      # Should have one child (the counter agent)
      assert map_size(state.children) == 1

      [{tag, child_info}] = Map.to_list(state.children)
      assert {:plugin, JidoTest.PluginLifecycleTest.ChatPlugin, _} = tag
      assert Process.alive?(child_info.pid)

      # Verify child state
      child_state = Agent.get(child_info.pid, & &1)
      assert child_state[:total_processed] == 0
      assert child_state[:started_at] != nil

      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # Tests: Full Lifecycle Integration
  # =============================================================================

  describe "full lifecycle integration" do
    test "all callbacks work together in a complete flow", %{jido: jido} do
      # 1. Create agent - mount/2 runs
      {:ok, pid} = Jido.AgentServer.start_link(agent: ConfiguredChatAgent, jido: jido)

      # 2. Verify child started - child_spec/1 ran
      initial_state = await_children(pid, 1)
      assert map_size(initial_state.children) == 1

      # 3. Verify mount state
      assert initial_state.agent.state[:chat][:session_id] == "test-session"
      assert initial_state.agent.state[:chat][:initialized_at] != nil

      # 4. Send signals - handle_signal/2 and transform_result/3 run
      for i <- 1..3 do
        signal =
          Signal.new!("chat.message", %{role: "user", content: "Message #{i}"}, source: "/test")

        {:ok, agent} = Jido.AgentServer.call(pid, signal)

        # Transform added metadata
        assert agent.state[:__chat_metadata__][:message_count] == i
      end

      # 5. Use a different signal type
      stats_signal = Signal.new!("chat.stats", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, stats_signal)

      assert agent.state[:chat][:last_stats][:message_count] == 3

      # 6. Verify rate limiting kicks in
      for i <- 4..5 do
        signal =
          Signal.new!("chat.message", %{role: "user", content: "Message #{i}"}, source: "/test")

        {:ok, _} = Jido.AgentServer.call(pid, signal)
      end

      # 6th should fail
      signal = Signal.new!("chat.message", %{role: "user", content: "Rejected"}, source: "/test")
      assert {:error, _} = Jido.AgentServer.call(pid, signal)

      # 7. Clear works even after rate limit
      clear_signal = Signal.new!("chat.clear", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, clear_signal)
      assert agent.state[:chat][:messages] == []

      GenServer.stop(pid)
    end

    test "agent without plugins still works normally", %{jido: jido} do
      defmodule NoPluginAction do
        use Jido.Action,
          name: "no_plugin_action",
          schema: []

        def run(_params, _context), do: {:ok, %{executed: true}}
      end

      defmodule NoPluginAgent do
        use Jido.Agent,
          name: "no_plugin_agent",
          schema: [counter: [type: :integer, default: 0]]

        def signal_routes(_ctx) do
          [{"test.action", JidoTest.PluginLifecycleTest.NoPluginAction}]
        end
      end

      {:ok, pid} = Jido.AgentServer.start_link(agent: NoPluginAgent, jido: jido)

      signal = Signal.new!("test.action", %{}, source: "/test")
      {:ok, agent} = Jido.AgentServer.call(pid, signal)

      # Agent works without plugins
      assert agent.id != nil

      {:ok, state} = Jido.AgentServer.state(pid)
      assert state.children == %{}

      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # Tests: Pure Agent (No AgentServer)
  # =============================================================================

  describe "pure agent usage (without AgentServer)" do
    test "cmd/2 works with plugin actions" do
      agent = ChatAgent.new()

      {agent, _directives} =
        ChatAgent.cmd(agent, {AddMessageAction, %{role: "user", content: "Hello"}})

      assert length(agent.state[:chat][:messages]) == 1
      assert hd(agent.state[:chat][:messages])[:content] == "Hello"
    end

    test "plugin state is accessible via plugin_state/2" do
      agent = ChatAgent.new()

      chat_state = ChatAgent.plugin_state(agent, ChatPlugin)

      assert chat_state[:messages] == []
      assert chat_state[:model] == "gpt-4"
      assert chat_state[:initialized_at] != nil
    end
  end
end
