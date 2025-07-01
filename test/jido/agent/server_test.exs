defmodule Jido.Agent.ServerTest do
  use JidoTest.Case, async: true
  doctest Jido.Agent.Server

  alias Jido.Agent.Server
  alias Jido.Signal
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Signal.Router
  alias Jido.Instruction

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
      assert Jido.Actions.Basic.Log in registered_actions
      assert Jido.Actions.Basic.Noop in registered_actions
      assert Jido.Actions.Basic.Sleep in registered_actions
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
      assert Jido.Actions.Basic.Log in registered_actions
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
      assert Jido.Actions.Basic.Log in registered_actions
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
      assert error.type == :routing_error
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

  describe "terminate race condition" do
    test "handles Process.info/2 race condition during termination" do
      # This test reproduces the bug where Process.info/2 throws ErlangError
      # when called on a dead process during the terminate callback

      # Create an agent that will be terminated
      {:ok, agent_pid} = Server.start_link(agent: BasicAgent, id: "terminate_race_test")

      # Verify agent is running
      assert Process.alive?(agent_pid)

      # The race condition happens when the process is dying and 
      # terminate/2 callback tries to get stacktrace via Process.info/2
      # 
      # Before our fix: This would throw ErlangError and crash
      # After our fix: This should complete gracefully

      # Monitor the agent to ensure it terminates properly
      ref = Process.monitor(agent_pid)

      # Stop the agent - this triggers the terminate/2 callback
      # which calls Process.info(self(), :current_stacktrace)
      GenServer.stop(agent_pid, :normal)

      # Verify the agent terminated normally without crashing
      # If the race condition bug exists, this might fail with a timeout
      # or receive a different exit reason
      assert_receive {:DOWN, ^ref, :process, ^agent_pid, :normal}, 1000

      # Additional verification that the process is actually dead
      refute Process.alive?(agent_pid)
    end

    test "handles Process.info/2 on external processes during cleanup" do
      # This test specifically targets the cleanup_task_group function
      # which calls Process.info(pid, :group_leader) on potentially dead processes

      # Create a temporary task that will die quickly
      task_pid =
        spawn(fn ->
          Process.sleep(1)
          # Process dies here
        end)

      # Wait for the task to die
      Process.sleep(10)
      refute Process.alive?(task_pid)

      # Before our fix: This would crash with ErlangError when 
      # Process.info(task_pid, :group_leader) is called on dead process
      # After our fix: This should handle the dead process gracefully

      # Create a fake task group (just a normal process)
      task_group =
        spawn(fn ->
          receive do
            :shutdown -> :ok
          after
            5000 -> :timeout
          end
        end)

      # This should not crash even though task_pid is dead
      # The cleanup logic should use Process.alive?/1 check first
      assert :ok = Jido.Exec.cleanup_task_group(task_group)

      # Clean up
      if Process.alive?(task_group) do
        Process.exit(task_group, :kill)
      end
    end
  end
end
