defmodule Jido.Agent.ServerDebugRuntimeTest do
  use ExUnit.Case, async: true

  alias Jido.Signal
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Runtime, as: ServerRuntime
  alias JidoTest.TestAgents.BasicAgent

  describe "debug runtime behavior" do
    @describetag :phase3

    # Helper function to collect all signals sent to the test process
    defp receive_all_signals(acc) do
      receive do
        {:signal, signal} -> receive_all_signals([signal | acc])
      after
        100 -> Enum.reverse(acc)
      end
    end

    setup do
      # Create a basic agent for testing
      agent = BasicAgent.new("test")

      # Create server state in debug mode
      state = %ServerState{
        agent: agent,
        mode: :debug,
        dispatch: {:logger, []}
      }

      # Create test signals
      signal1 =
        Signal.new!(%{
          id: "test-1",
          type: "test.action",
          data: %{action: "test", params: %{value: 1}}
        })

      signal2 =
        Signal.new!(%{
          id: "test-2",
          type: "test.action",
          data: %{action: "test", params: %{value: 2}}
        })

      signal3 =
        Signal.new!(%{
          id: "test-3",
          type: "test.action",
          data: %{action: "test", params: %{value: 3}}
        })

      %{
        state: state,
        signals: [signal1, signal2, signal3]
      }
    end

    test "in debug mode, only one signal is processed before pausing", %{
      state: state,
      signals: [s1, s2, s3]
    } do
      # Queue multiple signals
      {:ok, state} = ServerState.enqueue(state, s1)
      {:ok, state} = ServerState.enqueue(state, s2)
      {:ok, state} = ServerState.enqueue(state, s3)

      # Verify queue has 3 signals
      assert :queue.len(state.pending_signals) == 3

      # Process signals in debug mode
      result = ServerRuntime.process_signals_in_queue(state)

      # In debug mode, should return debug_break tuple after processing one signal
      assert {:debug_break, new_state, processed_signal} = result

      # Should have processed exactly one signal (the first one)
      assert processed_signal.id == s1.id
      assert :queue.len(new_state.pending_signals) == 2

      # Queue should still contain the remaining signals
      {:ok, next_signal, _} = ServerState.dequeue(new_state)
      assert next_signal.id == s2.id
    end

    test "debug events are emitted during processing", %{state: state, signals: signals} do
      s1 = Enum.at(signals, 0)
      # Set up event capturing
      test_pid = self()

      # Mock the output system to capture events
      state = %{state | dispatch: {:pid, [target: test_pid, delivery_mode: :async]}}

      # Queue one signal
      {:ok, state} = ServerState.enqueue(state, s1)

      # Process in debug mode
      {:debug_break, _new_state, _signal} = ServerRuntime.process_signals_in_queue(state)

      # Collect all received signals 
      signals = receive_all_signals([])

      # Should have debugger_pre_signal event
      pre_signals =
        Enum.filter(signals, fn sig ->
          String.contains?(sig.type, "debugger.pre.signal")
        end)

      assert length(pre_signals) >= 1
      pre_signal = hd(pre_signals)
      assert pre_signal.data.signal_id == s1.id

      # Should have debugger_post_signal event  
      post_signals =
        Enum.filter(signals, fn sig ->
          String.contains?(sig.type, "debugger.post.signal")
        end)

      assert length(post_signals) >= 1
      post_signal = hd(post_signals)
      assert post_signal.data.signal_id == s1.id
    end

    test "debug break tuple contains signal details", %{state: state, signals: signals} do
      s1 = Enum.at(signals, 0)
      {:ok, state} = ServerState.enqueue(state, s1)

      result = ServerRuntime.process_signals_in_queue(state)

      assert {:debug_break, new_state, signal} = result
      assert %Signal{} = signal
      assert signal.id == s1.id
      assert %ServerState{} = new_state
    end

    test "auto mode continues processing all signals", %{state: state, signals: [s1, s2, s3]} do
      # Set to auto mode
      state = %{state | mode: :auto}

      # Queue multiple signals
      {:ok, state} = ServerState.enqueue(state, s1)
      {:ok, state} = ServerState.enqueue(state, s2)
      {:ok, state} = ServerState.enqueue(state, s3)

      # Process all signals
      {:ok, final_state} = ServerRuntime.process_signals_in_queue(state)

      # All signals should be processed, queue should be empty
      assert :queue.len(final_state.pending_signals) == 0
    end

    test "step mode processes one signal and stops normally", %{state: state, signals: signals} do
      [s1, s2] = Enum.take(signals, 2)
      # Set to step mode  
      state = %{state | mode: :step}

      # Queue multiple signals
      {:ok, state} = ServerState.enqueue(state, s1)
      {:ok, state} = ServerState.enqueue(state, s2)

      # Process signals
      {:ok, final_state} = ServerRuntime.process_signals_in_queue(state)

      # Should process one signal and return normally (not debug_break)
      assert :queue.len(final_state.pending_signals) == 1
    end

    test "empty queue returns ok in debug mode", %{state: state} do
      # No signals in queue
      assert :queue.len(state.pending_signals) == 0

      # Process empty queue
      result = ServerRuntime.process_signals_in_queue(state)

      # Should return ok, not debug_break
      assert {:ok, _state} = result
    end
  end
end
