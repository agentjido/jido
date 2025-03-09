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
    # Store original log level
    original_level = Logger.level()
    Logger.configure(level: :debug)

    # Start a unique test registry for each test
    registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    on_exit(fn ->
      Logger.configure(level: original_level)
    end)

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
end
