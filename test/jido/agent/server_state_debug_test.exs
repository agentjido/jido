defmodule Jido.Agent.Server.StateDebugTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.State
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Signal

  @moduletag :capture_log
  @moduletag :phase1

  describe "debug mode support" do
    test "creates state with debug mode" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, mode: :debug}

      assert state.agent == agent
      assert state.mode == :debug
      assert state.status == :idle
      assert state.log_level == :info
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "accepts debug mode in struct creation with other fields" do
      agent = BasicAgent.new("test")
      dispatch = {:pid, [target: self()]}

      state = %State{
        agent: agent,
        mode: :debug,
        log_level: :debug,
        dispatch: dispatch
      }

      assert state.agent == agent
      assert state.mode == :debug
      assert state.log_level == :debug
      assert state.dispatch == dispatch
      assert state.status == :idle
    end

    test "debug mode struct is valid ServerState type" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, mode: :debug}

      # Verify it passes typespecs by using in function that expects ServerState.t()
      assert {:ok, cleared_state} = State.clear_queue(state)
      assert cleared_state.mode == :debug
    end

    test "debug mode works with state operations" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, mode: :debug}

      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "test-source",
          subject: "test-subject"
        })

      # Test enqueue works with debug mode
      assert {:ok, new_state} = State.enqueue(state, signal)
      assert new_state.mode == :debug
      assert :queue.len(new_state.pending_signals) == 1

      # Test dequeue works with debug mode  
      assert {:ok, dequeued_signal, final_state} = State.dequeue(new_state)
      assert final_state.mode == :debug
      assert dequeued_signal == signal
      assert :queue.is_empty(final_state.pending_signals)
    end

    test "debug mode works with state transitions" do
      agent = BasicAgent.new("test")

      state = %State{
        agent: agent,
        mode: :debug,
        dispatch: {:pid, [target: self()]}
      }

      # Test valid transition
      assert {:ok, new_state} = State.transition(state, :running)
      assert new_state.mode == :debug
      assert new_state.status == :running

      # Should emit transition signal
      assert_receive {:signal, %Signal{type: "jido.agent.event.transition.succeeded"}}
    end

    test "debug mode works with reply refs" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, mode: :debug}

      signal_id = "test-signal-id"
      from = {self(), make_ref()}

      state_with_ref = State.store_reply_ref(state, signal_id, from)
      assert state_with_ref.mode == :debug
      assert State.get_reply_ref(state_with_ref, signal_id) == from

      state_without_ref = State.remove_reply_ref(state_with_ref, signal_id)
      assert state_without_ref.mode == :debug
      assert State.get_reply_ref(state_without_ref, signal_id) == nil
    end
  end

  describe "debug mode with Agent.Server" do
    test "can start agent server with debug mode" do
      alias Jido.Agent.Server
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: "test-debug", mode: :debug)

      state = :sys.get_state(pid)
      assert state.mode == :debug
      assert state.agent.__struct__ == BasicAgent

      GenServer.stop(pid)
    end

    test "debug mode server state transitions work" do
      alias Jido.Agent.Server
      {:ok, pid} = Server.start_link(agent: BasicAgent, id: "test-debug-2", mode: :debug)

      state = :sys.get_state(pid)
      assert state.mode == :debug
      assert state.status == :idle

      GenServer.stop(pid)
    end
  end
end
