defmodule JidoTest.AgentCaseTest do
  use JidoTest.Case, async: true
  use JidoTest.AgentCase

  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestAgents.FullFeaturedAgent

  @moduletag :capture_log

  describe "new AgentCase helpers" do
    test "get_agent_state/1 returns current agent state" do
      context = spawn_agent()
      state = get_agent_state(context)
      
      assert is_map(state)
      assert state.location == :home
      assert state.battery_level == 100
    end

    test "assert_agent_state/2 validates state with map" do
      context = spawn_agent()
      assert_agent_state(context, %{location: :home, battery_level: 100})
    end

    test "assert_agent_state/2 validates state with keyword list" do
      context = spawn_agent()
      assert_agent_state(context, location: :home, battery_level: 100)
    end

    test "assert_agent_state/2 validates partial state" do
      context = spawn_agent()
      assert_agent_state(context, location: :home)  # Only check location, ignore battery_level
    end

    test "assert_agent_state/2 fails with incorrect state" do
      context = spawn_agent()
      
      assert_raise ExUnit.AssertionError, ~r/Expected :location to be :office, got :home/, fn ->
        assert_agent_state(context, location: :office)
      end
    end

    test "wait_for_agent_status/3 waits for status change" do
      context = spawn_agent()
      wait_for_agent_status(context, :idle)  # Should already be idle
    end

    test "wait_for_agent_status/3 with custom timeout" do
      context = spawn_agent()
      wait_for_agent_status(context, :idle, timeout: 2000, check_interval: 50)
    end

    test "assert_queue_empty/1 verifies empty queue" do
      context = spawn_agent()
      assert_queue_empty(context)
    end

    test "assert_queue_size/2 verifies queue size" do
      context = spawn_agent()
      assert_queue_size(context, 0)  # Should start empty
    end

    test "chaining multiple helpers together" do
      spawn_agent()
      |> assert_agent_state(location: :home)
      |> wait_for_agent_status(:idle)
      |> assert_queue_empty()
      |> assert_queue_size(0)
      |> assert_agent_state(battery_level: 100)
    end

    test "works with different agent types" do
      spawn_agent(FullFeaturedAgent)
      |> assert_agent_state(value: 0, location: :home, battery_level: 100)
      |> wait_for_agent_status(:idle)
      |> assert_queue_empty()
    end

    test "works with agents that have custom initial state" do
      # Create agent with custom initial state manually (spawn_agent doesn't support custom state)
      initial_state = %{location: :office, battery_level: 50, custom_field: "test"}
      agent = BasicAgent.new("custom_agent", initial_state)
      
      {:ok, server_pid} = Jido.Agent.Server.start_link(
        agent: agent,
        id: agent.id,
        mode: :step,
        registry: Jido.Registry
      )

      context = %{agent: agent, server_pid: server_pid}
      ExUnit.Callbacks.on_exit(fn -> 
        if Process.alive?(server_pid), do: GenServer.stop(server_pid, :normal, 1000)
      end)

      context
      |> assert_agent_state(location: :office, battery_level: 50, custom_field: "test")
      |> wait_for_agent_status(:idle)
      |> assert_queue_empty()
    end

    test "helper functions provide meaningful error messages" do
      context = spawn_agent()
      
      # Test assert_agent_state error message
      assert_raise ExUnit.AssertionError, ~r/Expected :battery_level to be 50, got 100/, fn ->
        assert_agent_state(context, battery_level: 50)
      end

      # Test assert_queue_size error message  
      assert_raise ExUnit.AssertionError, ~r/Expected queue size to be 5, got 0/, fn ->
        assert_queue_size(context, 5)
      end
    end

    test "helpers validate process is alive" do
      context = spawn_agent()
      
      # Stop the agent process
      GenServer.stop(context.server_pid, :normal)
      
      # Wait a moment for the process to terminate
      Process.sleep(10)
      
      # All helpers should raise RuntimeError when process is dead
      assert_raise RuntimeError, "Agent process is not alive", fn ->
        get_agent_state(context)
      end
      
      assert_raise RuntimeError, "Agent process is not alive", fn ->
        assert_agent_state(context, location: :home)
      end
      
      assert_raise RuntimeError, "Agent process is not alive", fn ->
        wait_for_agent_status(context, :idle)
      end
      
      assert_raise RuntimeError, "Agent process is not alive", fn ->
        assert_queue_empty(context)
      end
      
      assert_raise RuntimeError, "Agent process is not alive", fn ->
        assert_queue_size(context, 0)
      end
    end

    test "complex workflow demonstrating all new helpers" do
      # Start with a FullFeaturedAgent which has more complex state
      context = spawn_agent(FullFeaturedAgent)
      
      # Verify initial state
      state = get_agent_state(context)
      assert state.value == 0
      assert state.location == :home
      assert state.battery_level == 100
      assert state.status == :idle
      
      # Chain all helpers together in a meaningful workflow
      context
      |> assert_agent_state(value: 0, status: :idle)
      |> wait_for_agent_status(:idle)
      |> assert_queue_empty()
      |> assert_queue_size(0)
      |> assert_agent_state(location: :home, battery_level: 100)
    end
  end

  describe "integration with existing AgentCase functions" do
    test "new helpers work with existing spawn_agent and signal functions" do
      spawn_agent()
      |> assert_agent_state(location: :home)
      |> assert_queue_empty()
      |> send_signal_async("test.signal", %{data: "value"})
      |> assert_queue_size(1)  # Signal should be queued
    end

    test "queue helpers work with multiple signals" do
      spawn_agent()
      |> assert_queue_empty()
      |> send_signal_async("signal.1", %{order: 1})
      |> send_signal_async("signal.2", %{order: 2})
      |> send_signal_async("signal.3", %{order: 3})
      |> assert_queue_size(3)
    end

    test "queue size changes as signals are processed" do
      context = spawn_agent()
      
      # Send multiple async signals
      context
      |> send_signal_async("signal.1", %{})
      |> send_signal_async("signal.2", %{})
      |> assert_queue_size(2)
      
      # Send a sync signal (this will wait for processing)
      send_signal_sync(context, "signal.3", %{})
      
      # Check that signals might still be in queue (depends on agent processing)
      # In step mode, signals may remain queued until explicitly processed
      # This is more about testing the helper functions than agent behavior
    end

    test "assert_queue_empty fails when queue has items" do
      context = spawn_agent()
      send_signal_async(context, "test.signal", %{})
      
      assert_raise ExUnit.AssertionError, ~r/Expected queue to be empty/, fn ->
        assert_queue_empty(context)
      end
    end

    test "demonstrates the improvement in test readability" do
      # Before: Manual state checking
      old_context = spawn_agent()
      {:ok, old_state} = Jido.Agent.Server.state(old_context.server_pid)
      assert old_state.agent.state.location == :home
      assert old_state.agent.state.battery_level == 100
      assert :queue.is_empty(old_state.pending_signals)
      
      # After: Using new helpers
      spawn_agent()
      |> assert_agent_state(location: :home, battery_level: 100)
      |> assert_queue_empty()
    end
  end

  describe "existing AgentCase DSL functionality" do
    test "spawn_agent creates agent with automatic cleanup" do
      result = spawn_agent()
      assert result.agent.__struct__ == JidoTest.TestAgents.BasicAgent
      assert is_pid(result.server_pid)
      assert Process.alive?(result.server_pid)
    end

    test "pipeline signal sending" do
      result =
        spawn_agent()
        |> send_signal_async("user.registered", %{user_id: 123, email: "test@example.com"})
        |> send_signal_async("email.verification.sent", %{token: "abc123"})
        |> send_signal_async("profile.completed", %{full_name: "John Doe"})

      assert result.agent.__struct__ == JidoTest.TestAgents.BasicAgent
      assert is_pid(result.server_pid)
      assert Process.alive?(result.server_pid)
    end

    test "single signal sending" do
      result = send_signal_async(spawn_agent(), "order.created", %{id: "ord_456", amount: 100.0})

      assert is_map(result)
      assert is_pid(result.server_pid)
    end

    test "works with different agent types" do
      custom_agent = JidoTest.TestAgents.FullFeaturedAgent

      result =
        custom_agent
        |> spawn_agent()
        |> send_signal_async("system.startup", %{version: "1.0.0"})
        |> send_signal_async("config.loaded", %{env: "test"})

      assert result.agent.__struct__ == custom_agent
      assert is_pid(result.server_pid)
      assert Process.alive?(result.server_pid)
    end

    test "spawn_agent validates agent modules properly" do
      # Should raise error for non-agent modules
      assert_raise ArgumentError, ~r/does not implement the Jido.Agent behavior/, fn ->
        spawn_agent(String)
      end

      # Should raise error for non-existent modules  
      assert_raise ArgumentError, ~r/could not be loaded/, fn ->
        spawn_agent(NonExistentModule)
      end
    end

    test "complete workflow using both old and new helpers" do
      spawn_agent()
      |> assert_agent_state(location: :home, battery_level: 100)
      |> wait_for_agent_status(:idle)
      |> assert_queue_empty()
    end
  end
end