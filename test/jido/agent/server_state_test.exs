defmodule Jido.Agent.Server.StateTest do
  use JidoTest.Case, async: true
  alias Jido.Agent.Server.State
  alias JidoTest.TestAgents.BasicAgent
  alias Jido.Signal

  @moduletag :capture_log

  setup do
    {:ok, current_signal} =
      Signal.new(%{
        id: "test-signal-123",
        type: "test.signal",
        source: "test-source",
        subject: "test-subject",
        jido_dispatch: {:logger, []}
      })

    state = %State{
      agent: %{id: "test-agent-123", __struct__: TestAgent},
      dispatch: {:logger, []},
      current_signal: current_signal
    }

    {:ok, state: state}
  end

  describe "new state" do
    test "creates state with required fields" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent}

      assert state.agent == agent
      assert state.dispatch == {:logger, []}
      assert state.status == :idle
      assert state.log_level == :info
      assert state.mode == :auto
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "creates state with custom output config" do
      agent = BasicAgent.new("test")
      dispatch = {:pid, [target: self()]}
      state = %State{agent: agent, dispatch: dispatch}

      assert state.agent == agent
      assert state.dispatch == dispatch
      assert state.status == :idle
      assert state.log_level == :info
      assert state.mode == :auto
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "creates state with custom log_level and mode settings" do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, log_level: :debug, mode: :step}

      assert state.agent == agent
      assert state.log_level == :debug
      assert state.mode == :step
      assert state.status == :idle
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end

    test "initializes with default values", %{state: state} do
      assert state.status == :idle
      assert state.mode == :auto
      assert state.log_level == :info
      assert state.max_queue_size == 10_000
      assert state.dispatch == {:logger, []}
      assert :queue.is_queue(state.pending_signals)
      assert :queue.is_empty(state.pending_signals)
    end
  end

  describe "transition/2" do
    setup do
      agent = BasicAgent.new("test")
      state = %State{agent: agent, dispatch: {:pid, [target: self()]}}
      {:ok, state: state}
    end

    test "handles self-transitions as a noop", %{state: state} do
      # Test self-transition from idle state
      state = %{state | status: :idle}
      assert {:ok, %State{status: :idle}} = State.transition(state, :idle)
      # No transition signal should be emitted for self-transitions
      refute_receive {:signal, _}

      # Test self-transition from running state
      state = %{state | status: :running}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)
      refute_receive {:signal, _}
    end

    test "allows valid transitions and emits signals", %{state: state} do
      # initializing -> idle
      state = %{state | status: :initializing}
      transition_succeeded = "jido.agent.event.transition.succeeded"
      assert {:ok, %State{status: :idle}} = State.transition(state, :idle)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :initializing, to: :idle}
                      }}

      # idle -> planning
      state = %{state | status: :idle}
      assert {:ok, %State{status: :planning}} = State.transition(state, :planning)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :idle, to: :planning}
                      }}

      # planning -> running
      state = %{state | status: :planning}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :planning, to: :running}
                      }}

      # running -> paused
      state = %{state | status: :running}
      assert {:ok, %State{status: :paused}} = State.transition(state, :paused)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :running, to: :paused}
                      }}

      # paused -> running
      state = %{state | status: :paused}
      assert {:ok, %State{status: :running}} = State.transition(state, :running)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_succeeded,
                        data: %{from: :paused, to: :running}
                      }}
    end

    test "rejects invalid transitions and emits failure signals", %{state: state} do
      # Can't go from idle to paused
      state = %{state | status: :idle}
      transition_failed = "jido.agent.event.transition.failed"
      assert {:error, {:invalid_transition, :idle, :paused}} = State.transition(state, :paused)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_failed,
                        data: %{from: :idle, to: :paused}
                      }}

      # Can't go from running to planning
      state = %{state | status: :running}

      assert {:error, {:invalid_transition, :running, :planning}} =
               State.transition(state, :planning)

      assert_receive {:signal,
                      %Signal{
                        type: ^transition_failed,
                        data: %{from: :running, to: :planning}
                      }}
    end
  end

  describe "enqueue/2" do
    test "successfully enqueues a signal", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      assert {:ok, new_state} = State.enqueue(state, signal)
      assert :queue.len(new_state.pending_signals) == 1
    end

    test "maintains FIFO order", %{state: state} do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, state_with_one} = State.enqueue(state, signal1)
      {:ok, state_with_two} = State.enqueue(state_with_one, signal2)

      assert :queue.len(state_with_two.pending_signals) == 2

      {:ok, first_signal, state_with_one} = State.dequeue(state_with_two)
      assert first_signal.type == "test.signal.1"

      {:ok, second_signal, empty_state} = State.dequeue(state_with_one)
      assert second_signal.type == "test.signal.2"

      assert :queue.is_empty(empty_state.pending_signals)
    end

    test "returns error and emits overflow signal when queue is at max capacity", %{state: state} do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      state = %{state | max_queue_size: 1}
      {:ok, state_with_one} = State.enqueue(state, signal1)

      assert {:error, :queue_overflow} = State.enqueue(state_with_one, signal2)
      assert :queue.len(state_with_one.pending_signals) == 1
    end
  end

  describe "enqueue_front/2" do
    test "successfully enqueues signal at front of queue", %{state: state} do
      # Create 4 test signals
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal3} =
        Signal.new(%{
          type: "test.signal.3",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal4} =
        Signal.new(%{
          type: "test.signal.4",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      # Build up queue with mix of enqueue and enqueue_front
      {:ok, state_with_one} = State.enqueue(state, signal1)
      {:ok, state_with_two} = State.enqueue_front(state_with_one, signal2)
      {:ok, state_with_three} = State.enqueue(state_with_two, signal3)
      {:ok, state_with_four} = State.enqueue_front(state_with_three, signal4)

      assert :queue.len(state_with_four.pending_signals) == 4

      # Verify signals come out in expected order:
      # signal4 (front), signal2, signal1, signal3 (back)

      {:ok, first_signal, state_with_three} = State.dequeue(state_with_four)
      assert first_signal.type == "test.signal.4"

      {:ok, second_signal, state_with_two} = State.dequeue(state_with_three)
      assert second_signal.type == "test.signal.2"

      {:ok, third_signal, state_with_one} = State.dequeue(state_with_two)
      assert third_signal.type == "test.signal.1"

      {:ok, fourth_signal, empty_state} = State.dequeue(state_with_one)
      assert fourth_signal.type == "test.signal.3"

      assert :queue.is_empty(empty_state.pending_signals)
    end

    test "returns error and emits overflow signal when queue is at max capacity", %{state: state} do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      state = %{state | max_queue_size: 1}
      {:ok, state_with_one} = State.enqueue(state, signal1)

      assert {:error, :queue_overflow} = State.enqueue_front(state_with_one, signal2)
      assert :queue.len(state_with_one.pending_signals) == 1
    end
  end

  describe "dequeue/1" do
    test "successfully dequeues a signal", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, state_with_signal} = State.enqueue(state, signal)
      assert {:ok, dequeued_signal, new_state} = State.dequeue(state_with_signal)
      assert dequeued_signal == signal
      assert :queue.is_empty(new_state.pending_signals)
    end

    test "returns error when queue is empty", %{state: state} do
      assert {:error, :empty_queue} = State.dequeue(state)
    end
  end

  describe "clear_queue/1" do
    test "clears all signals from the queue and emits signal", %{state: state} do
      {:ok, signal1} =
        Signal.new(%{
          type: "test.signal.1",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, signal2} =
        Signal.new(%{
          type: "test.signal.2",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, state_with_one} = State.enqueue(state, signal1)
      {:ok, state_with_two} = State.enqueue(state_with_one, signal2)

      assert :queue.len(state_with_two.pending_signals) == 2

      {:ok, cleared_state} = State.clear_queue(state_with_two)
      assert :queue.is_empty(cleared_state.pending_signals)
    end

    test "clearing an empty queue emits signal with zero size", %{state: state} do
      {:ok, cleared_state} = State.clear_queue(state)
      assert :queue.is_empty(cleared_state.pending_signals)
    end
  end

  describe "check_queue_size/1" do
    test "returns error when queue size exceeds maximum", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      state = %{state | max_queue_size: 0}
      assert {:error, :queue_overflow} = State.enqueue(state, signal)
    end

    test "returns current size when within limits", %{state: state} do
      {:ok, signal} =
        Signal.new(%{
          type: "test.signal",
          source: "test-source",
          subject: "test-subject",
          jido_dispatch: {:logger, []}
        })

      {:ok, state_with_signal} = State.enqueue(state, signal)
      assert {:ok, 1} = State.check_queue_size(state_with_signal)
    end
  end

  describe "reply_refs" do
    test "stores and retrieves reply refs", %{state: state} do
      signal_id = "test-signal-id"
      from = {self(), make_ref()}

      state_with_ref = State.store_reply_ref(state, signal_id, from)
      assert State.get_reply_ref(state_with_ref, signal_id) == from

      state_without_ref = State.remove_reply_ref(state_with_ref, signal_id)
      assert State.get_reply_ref(state_without_ref, signal_id) == nil
    end
  end
end
