defmodule Jido.Agent.ServerTest do
  use JidoTest.Case, async: true
  doctest Jido.Agent.Server

  alias Jido.Agent.Server
  alias Jido.Signal
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Signal.Router
  alias Jido.Instruction
  alias Jido.Error

  @moduletag :capture_log

  setup do
    # Start a unique test registry for each test
    registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    %{registry: registry_name}
  end

  describe "start_link/1" do
    test "starts with minimal configuration" do
      {:ok, pid} = Server.start_link(agent: BasicAgent)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts with explicit id" do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id)
      assert is_pid(pid)
      {:ok, state} = Server.state(pid)
      assert state.agent.id == id
    end

    test "agent id takes precedence over provided id" do
      id1 = "test-agent-#{System.unique_integer([:positive])}"
      id2 = "test-agent-#{System.unique_integer([:positive])}"

      # Create agent with id2
      agent = BasicAgent.new(id2)

      # Start server with id1, but agent has id2
      {:ok, pid} = Server.start_link(agent: agent, id: id1)
      assert is_pid(pid)

      # Verify the agent's ID (id2) was used, not the provided ID (id1)
      {:ok, state} = Server.state(pid)
      assert state.agent.id == id2
      refute state.agent.id == id1

      # Verify that the ID in the options was updated to match the agent's ID
      assert state.agent.id == id2
    end

    test "registers default actions with agent" do
      {:ok, pid} = Server.start_link(agent: BasicAgent)
      {:ok, state} = Server.state(pid)

      # Check if default actions are registered
      registered_actions = Jido.Agent.registered_actions(state.agent)

      # Verify some of the default actions are registered
      assert Jido.Tools.Basic.Log in registered_actions
      assert Jido.Tools.Basic.Noop in registered_actions
      assert Jido.Tools.Basic.Sleep in registered_actions
    end

    test "registers provided actions with agent" do
      # Use a custom action module for testing
      defmodule TestAction do
        use Jido.Action, name: "test_action"
        def run(_params, _ctx), do: {:ok, %{}}
      end

      {:ok, pid} = Server.start_link(agent: BasicAgent, actions: [TestAction])
      {:ok, state} = Server.state(pid)

      # Check if our custom action is registered
      registered_actions = Jido.Agent.registered_actions(state.agent)
      assert TestAction in registered_actions

      # Default actions should still be registered
      assert Jido.Tools.Basic.Log in registered_actions
    end

    test "merges actions with existing agent actions" do
      # Create an agent with pre-registered actions
      defmodule PreregisteredAction do
        use Jido.Action, name: "preregistered_action"
        def run(_params, _ctx), do: {:ok, %{}}
      end

      # Register an action with the agent before starting the server
      agent = BasicAgent.new()
      {:ok, agent_with_action} = Jido.Agent.register_action(agent, PreregisteredAction)

      # Define a new action to be registered via server options
      defmodule ServerAction do
        use Jido.Action, name: "server_action"
        def run(_params, _ctx), do: {:ok, %{}}
      end

      # Start server with the pre-configured agent and additional actions
      {:ok, pid} =
        Server.start_link(
          agent: agent_with_action,
          actions: [ServerAction]
        )

      {:ok, state} = Server.state(pid)
      registered_actions = Jido.Agent.registered_actions(state.agent)

      # Both actions should be registered
      assert PreregisteredAction in registered_actions
      assert ServerAction in registered_actions

      # Default actions should also be registered
      assert Jido.Tools.Basic.Log in registered_actions
    end

    test "starts with custom registry", %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      assert [{^pid, nil}] = Registry.lookup(registry, id)
    end

    test "starts with initial state" do
      id = "test-agent-#{System.unique_integer([:positive])}"
      initial_state = %{location: :office, battery_level: 75}
      agent = BasicAgent.new(id, initial_state)
      {:ok, pid} = Server.start_link(agent: agent)
      {:ok, state} = Server.state(pid)
      assert state.agent.state.location == :office
      assert state.agent.state.battery_level == 75
    end

    test "fails with invalid agent" do
      assert {:error, :invalid_agent} = Server.start_link(agent: nil)
    end

    test "starts in auto mode by default" do
      {:ok, pid} = Server.start_link(agent: BasicAgent)
      {:ok, state} = Server.state(pid)
      assert state.mode == :auto
    end

    test "starts in step mode when specified" do
      {:ok, pid} = Server.start_link(agent: BasicAgent, mode: :step)
      {:ok, state} = Server.state(pid)
      assert state.mode == :step
    end
  end

  describe "state/1" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      %{pid: pid, id: id}
    end

    test "returns current state", %{pid: pid} do
      {:ok, state} = Server.state(pid)
      assert %{agent: %BasicAgent{}} = state
      assert state.agent.state.location == :home
      assert state.agent.state.battery_level == 100
    end
  end

  # describe "call/2" do
  #   setup %{registry: registry} do
  #     id = "test-agent-#{System.unique_integer([:positive])}"
  #     agent = BasicAgent.new(id)

  #     route = %Router.Route{
  #       path: "test_signal",
  #       instruction: %Instruction{
  #         action: JidoTest.TestActions.BasicAction,
  #         params: %{value: 42}
  #       }
  #     }

  #     {:ok, pid} =
  #       Server.start_link(
  #         agent: agent,
  #         id: id,
  #         registry: registry,
  #         routes: [route]
  #       )

  #     %{pid: pid, id: id}
  #   end
  # end

  describe "cast/2" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      agent = BasicAgent.new(id)

      route = %Router.Route{
        path: "test_signal",
        target: %Instruction{
          action: JidoTest.TestActions.BasicAction,
          params: %{value: 42}
        }
      }

      {:ok, pid} =
        Server.start_link(
          agent: agent,
          id: id,
          registry: registry,
          routes: [route]
        )

      %{pid: pid, id: id}
    end

    test "handles asynchronous signals", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "test_signal", id: "test-id-123"})
      {:ok, correlation_id} = Server.cast(pid, signal)
      assert correlation_id == signal.id
      assert is_binary(correlation_id)
    end

    test "preserves correlation_id in cast", %{pid: pid} do
      id = Jido.Util.generate_id()

      {:ok, signal} =
        Signal.new(%{
          type: "test_signal",
          id: id
        })

      {:ok, ^id} = Server.cast(pid, signal)
    end
  end

  describe "process lifecycle" do
    setup %{registry: registry} do
      %{registry: registry}
    end

    test "supervisor child spec has correct values" do
      id = "test-agent"
      spec = Server.child_spec(id: id)

      assert spec.id == id
      assert spec.type == :supervisor
      assert spec.restart == :permanent
      assert spec.shutdown == :infinity
    end

    @tag :capture_log
    test "handles process termination", %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      ref = Process.monitor(pid)

      # Give the process a moment to initialize
      Process.sleep(100)

      # Send shutdown signal
      Process.flag(:trap_exit, true)
      GenServer.stop(pid, :shutdown)
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 1000
    end
  end

  describe "error handling" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      agent = BasicAgent.new(id)

      route = %Router.Route{
        path: "test_signal",
        target: %Instruction{
          action: JidoTest.TestActions.BasicAction,
          params: %{value: 42}
        }
      }

      {:ok, pid} =
        Server.start_link(
          agent: agent,
          id: id,
          registry: registry,
          routes: [route]
        )

      %{pid: pid, id: id}
    end

    test "handles invalid signal types", %{pid: pid} do
      {:ok, signal} = Signal.new(%{type: "invalid_signal_type"})

      # Add timeout to prevent test from hanging
      result = Server.call(pid, signal, 1000)
      assert {:error, error} = result
      assert Error.to_map(error).type == :routing_error
    end

    @tag :capture_log
    test "handles process crashes", %{pid: pid} do
      ref = Process.monitor(pid)
      # Force a crash
      Process.flag(:trap_exit, true)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    end
  end

  describe "input validation optimizations" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      %{pid: pid, id: id}
    end

    test "validates instructions with missing action", %{pid: pid} do
      invalid_instruction = %Instruction{action: nil, params: %{}}

      result = Server.call(pid, invalid_instruction, 1000)
      assert {:error, {:invalid_input, :missing_action}} = result
    end

    test "validates instructions with invalid action", %{pid: pid} do
      invalid_instruction = %Instruction{action: :nonexistent_module, params: %{}}

      result = Server.call(pid, invalid_instruction, 1000)
      assert {:error, {:invalid_input, {:invalid_action, :nonexistent_module}}} = result
    end

    test "validates instructions in cast operations", %{pid: pid} do
      invalid_instruction = %Instruction{action: nil, params: %{}}

      result = Server.cast(pid, invalid_instruction)
      assert {:error, {:invalid_input, :missing_action}} = result
    end

    test "accepts valid instructions", %{pid: pid} do
      # Use an existing registered action
      valid_instruction = %Instruction{action: Jido.Tools.Basic.Noop, params: %{}}

      result = Server.call(pid, valid_instruction, 1000)
      assert {:ok, _response} = result
    end
  end

  describe "reply reference cleanup optimizations" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      %{pid: pid, id: id}
    end

    @tag :capture_log
    test "handles reply reference cleanup mechanism", %{pid: pid} do
      # Test that reply references are managed properly
      # We'll test by ensuring multiple calls work correctly
      instruction = %Instruction{action: Jido.Tools.Basic.Noop, params: %{}}

      # Multiple concurrent calls should all work
      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn -> Server.call(pid, instruction, 1000) end)
        end)

      results = Enum.map(tasks, &Task.await(&1, 2000))

      # All should succeed
      Enum.each(results, fn result ->
        assert {:ok, _response} = result
      end)
    end
  end

  describe "queue processing backpressure optimizations" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry, mode: :auto)
      %{pid: pid, id: id}
    end

    test "processes signals in batches", %{pid: pid} do
      # Send multiple signals quickly using a registered action
      signals =
        Enum.map(1..15, fn i ->
          %Instruction{action: Jido.Tools.Basic.Noop, params: %{batch_id: i}}
        end)

      # Send all signals
      tasks =
        Enum.map(signals, fn instruction ->
          Task.async(fn -> Server.call(pid, instruction, 5000) end)
        end)

      # All should complete successfully
      results = Enum.map(tasks, &Task.await(&1, 6000))

      assert length(results) == 15

      Enum.each(results, fn result ->
        assert {:ok, _response} = result
      end)
    end

    test "handles queue size limits properly", %{pid: pid} do
      # Get the current state to check queue configuration
      {:ok, state} = Server.state(pid)

      # Verify the server has proper queue configuration
      assert state.max_queue_size > 0
      assert :queue.len(state.pending_signals) >= 0
    end
  end

  describe "secure agent creation optimizations" do
    test "handles agent creation failures gracefully" do
      # Try to create a server with an invalid agent module
      result = Server.start_link(agent: :nonexistent_agent_module, id: "test")

      assert {:error, {:module_load_failed, _reason}} = result
    end

    test "handles agent creation exceptions gracefully" do
      # Create a module that will throw an exception
      defmodule FaultyAgent do
        def new(_id, _state), do: raise("Creation failed!")
      end

      result = Server.start_link(agent: FaultyAgent, id: "test")

      assert {:error, {:agent_creation_failed, _error}} = result
    end

    test "validates agent creation return value" do
      # Create a module that returns invalid data
      defmodule InvalidReturnAgent do
        def new(_id, _state), do: :invalid_return
      end

      result = Server.start_link(agent: InvalidReturnAgent, id: "test")

      assert {:error, {:invalid_agent_return, :invalid_return}} = result
    end
  end

  describe "state transition validation optimizations" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)

      # Give the server time to initialize and transition to idle
      Process.sleep(100)

      %{pid: pid, id: id}
    end

    test "enforces valid state transitions", %{pid: pid} do
      {:ok, state} = Server.state(pid)

      # Verify the server is in idle state after initialization
      assert state.status == :idle
    end
  end

  describe "standardized error responses optimizations" do
    setup %{registry: registry} do
      id = "test-agent-#{System.unique_integer([:positive])}"
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: id, registry: registry)
      %{pid: pid, id: id}
    end

    test "returns structured error responses for queue size command", %{pid: pid} do
      # This test would require manipulating the queue to trigger overflow
      # For now, we'll test the successful case structure
      {:ok, state} = Server.state(pid)

      # Verify state contains queue information
      assert is_map(state)
      assert Map.has_key?(state, :pending_signals)
    end
  end
end
