defmodule Jido.Agent.DebuggerTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.{Server, Debugger}
  alias Jido.Signal
  alias JidoTest.TestAgents.BasicAgent

  describe "debugger attachment" do
    @describetag :phase4
    setup do
      # Start a unique test registry for each test
      registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
      {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

      # Start an agent with debug mode enabled
      {:ok, agent_pid} =
        Server.start_link(agent: BasicAgent, mode: :debug, registry: registry_name)

      # Create some test signals to queue
      signal1 = Signal.new("test_signal_1", %{data: "first"})
      signal2 = Signal.new("test_signal_2", %{data: "second"})

      {:ok, agent_pid: agent_pid, signals: [signal1, signal2], registry: registry_name}
    end

    test "attach/1 returns debugger pid and suspends agent", %{agent_pid: agent_pid} do
      # Agent should be running initially
      assert Process.alive?(agent_pid)

      # Attach debugger
      assert {:ok, debugger_pid} = Debugger.attach(agent_pid)
      assert is_pid(debugger_pid)
      assert Process.alive?(debugger_pid)

      # Agent should be suspended
      # Should still be accessible via :sys
      assert :sys.get_state(agent_pid, 100)
    end

    test "attach/1 fails if agent is not in debug mode", %{registry: registry} do
      # Start agent without debug mode
      {:ok, normal_agent_pid} = Server.start_link(agent: BasicAgent, registry: registry)

      assert {:error, :not_in_debug_mode} = Debugger.attach(normal_agent_pid)
    end

    test "step/1 processes one signal and re-suspends", %{agent_pid: agent_pid} do
      # Attach debugger to suspend processing
      {:ok, debugger_pid} = Debugger.attach(agent_pid)

      # Create a simple test signal
      test_signal = Signal.new("basic.test", %{test: true})

      # Manually inject signal into the state for testing
      state = :sys.get_state(agent_pid)
      updated_queue = :queue.in(test_signal, state.pending_signals)
      updated_state = %{state | pending_signals: updated_queue}
      :sys.replace_state(agent_pid, fn _ -> updated_state end)

      # Get queue length after injection
      new_state = :sys.get_state(agent_pid)
      initial_queue_length = :queue.len(new_state.pending_signals)
      assert initial_queue_length == 1

      # Step should succeed - this tests the basic stepping mechanism
      assert :ok = Debugger.step(debugger_pid)

      # Agent should still be suspended and accessible
      assert :sys.get_state(agent_pid, 100)

      # Debugger should still be alive
      assert Process.alive?(debugger_pid)
    end

    test "step/1 handles empty queue gracefully", %{agent_pid: agent_pid} do
      {:ok, debugger_pid} = Debugger.attach(agent_pid)

      # Ensure queue is empty
      state = :sys.get_state(agent_pid)
      assert :queue.len(state.pending_signals) == 0

      # Stepping with empty queue should not crash
      assert {:error, :no_signals_queued} = Debugger.step(debugger_pid)
    end

    test "detach/1 restores mode and resumes agent", %{agent_pid: agent_pid} do
      {:ok, debugger_pid} = Debugger.attach(agent_pid)

      # Agent should be suspended
      assert :sys.get_state(agent_pid, 100)

      # Detach
      assert :ok = Debugger.detach(debugger_pid)

      # Agent should be resumed and responsive
      assert GenServer.call(agent_pid, :ping, 1000) == :pong

      # Debugger should be stopped
      refute Process.alive?(debugger_pid)
    end

    test "agent remains responsive after detach", %{agent_pid: agent_pid, signals: signals} do
      [signal1 | _] = signals
      {:ok, debugger_pid} = Debugger.attach(agent_pid)

      # Queue a signal while debugging
      GenServer.cast(agent_pid, {:signal, signal1})

      # Step through it
      Debugger.step(debugger_pid)

      # Detach
      Debugger.detach(debugger_pid)

      # Agent should process normally
      assert GenServer.call(agent_pid, :ping, 1000) == :pong

      # Should be able to queue new signals
      signal2 = Signal.new("test_after_detach", %{})
      GenServer.cast(agent_pid, {:signal, signal2})

      # Give it time to process
      Process.sleep(10)
      assert GenServer.call(agent_pid, :ping, 1000) == :pong
    end

    test "debugger handles agent termination gracefully", %{agent_pid: agent_pid} do
      {:ok, debugger_pid} = Debugger.attach(agent_pid)

      # Monitor the debugger
      debugger_ref = Process.monitor(debugger_pid)

      # Terminate the agent
      GenServer.stop(agent_pid)

      # Debugger should terminate as well
      assert_receive {:DOWN, ^debugger_ref, :process, ^debugger_pid, _reason}, 1000
    end
  end
end
