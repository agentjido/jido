defmodule Jido.Agent.Server.SignalProcessorTest do
  use JidoTest.Case, async: true
  doctest Jido.Agent.Server.SignalProcessor

  alias Jido.Agent.Server.SignalProcessor
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Signal
  alias Jido.Instruction
  alias JidoTest.TestAgents.BasicAgent

  @moduletag :capture_log

  setup do
    # Create a basic server state for testing
    agent = BasicAgent.new("test-agent-#{System.unique_integer([:positive])}")

    state = %ServerState{
      agent: agent,
      mode: :auto,
      log_level: :info,
      max_queue_size: 100,
      registry: Jido.Registry,
      dispatch: nil,
      skills: [],
      pending_signals: :queue.new(),
      reply_refs: %{},
      current_signal: nil,
      status: :idle
    }

    %{state: state}
  end

  describe "process_signal_batch/2" do
    test "returns error when queue is empty", %{state: state} do
      result = SignalProcessor.process_signal_batch(state, 10)
      assert {:error, :empty_queue} = result
    end

    test "processes single signal successfully", %{state: state} do
      # Create an instruction signal
      instruction = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      # Enqueue the signal
      {:ok, state_with_signal} = ServerState.enqueue(state, signal)

      # Process the batch
      result = SignalProcessor.process_signal_batch(state_with_signal, 10)

      assert {:ok, new_state, [], :queue_empty} = result
      assert :queue.len(new_state.pending_signals) == 0
    end

    test "processes multiple signals in batch", %{state: state} do
      # Create multiple instruction signals
      signals =
        for i <- 1..3 do
          instruction =
            Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{index: i}})

          {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})
          signal
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = ServerState.enqueue(acc_state, signal)
          new_state
        end)

      # Process the batch
      result = SignalProcessor.process_signal_batch(state_with_signals, 10)

      assert {:ok, new_state, [], :queue_empty} = result
      assert :queue.len(new_state.pending_signals) == 0
    end

    test "respects batch size limit", %{state: state} do
      # Create more signals than batch size
      signals =
        for i <- 1..5 do
          instruction =
            Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{index: i}})

          {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})
          signal
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = ServerState.enqueue(acc_state, signal)
          new_state
        end)

      # Process with batch size of 3
      result = SignalProcessor.process_signal_batch(state_with_signals, 3)

      assert {:ok, new_state, [], :more_signals} = result
      # 5 - 3 = 2 remaining
      assert :queue.len(new_state.pending_signals) == 2
    end

    test "handles step mode correctly", %{state: state} do
      # Set state to step mode
      step_state = %{state | mode: :step}

      # Create multiple signals
      signals =
        for i <- 1..3 do
          instruction =
            Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{index: i}})

          {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})
          signal
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, step_state, fn signal, acc_state ->
          {:ok, new_state} = ServerState.enqueue(acc_state, signal)
          new_state
        end)

      # Process the batch - should only process one signal in step mode
      result = SignalProcessor.process_signal_batch(state_with_signals, 10)

      assert {:ok, new_state, [], :more_signals} = result
      # Only processed 1 signal
      assert :queue.len(new_state.pending_signals) == 2
    end

    test "handles reply references correctly", %{state: state} do
      # Create an instruction signal
      instruction = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      # Store reply reference
      fake_from = make_ref()
      state_with_reply = ServerState.store_reply_ref(state, signal.id, fake_from)

      # Enqueue the signal
      {:ok, state_with_signal} = ServerState.enqueue(state_with_reply, signal)

      # Process the batch
      result = SignalProcessor.process_signal_batch(state_with_signal, 10)

      assert {:ok, new_state, replies, :queue_empty} = result
      assert [{^fake_from, {:ok, _result}}] = replies
      assert ServerState.get_reply_ref(new_state, signal.id) == nil
    end
  end

  describe "process_one_signal/1" do
    test "returns error when queue is empty", %{state: state} do
      result = SignalProcessor.process_one_signal(state)
      assert {:error, :empty_queue} = result
    end

    test "processes instruction signal", %{state: state} do
      # Create an instruction signal
      instruction = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      # Enqueue the signal
      {:ok, state_with_signal} = ServerState.enqueue(state, signal)

      # Process one signal
      result = SignalProcessor.process_one_signal(state_with_signal)

      assert {:ok, new_state, []} = result
      assert :queue.len(new_state.pending_signals) == 0
    end

    test "handles processing errors gracefully", %{state: state} do
      # Create a signal with invalid data
      {:ok, signal} = Signal.new(%{type: "instruction", data: "invalid"})

      # Enqueue the signal
      {:ok, state_with_signal} = ServerState.enqueue(state, signal)

      # Process one signal
      result = SignalProcessor.process_one_signal(state_with_signal)

      assert {:ok, new_state, []} = result
      assert :queue.len(new_state.pending_signals) == 0
    end
  end

  describe "execute_signal_for_state_machine/2" do
    test "executes instruction signals", %{state: state} do
      instruction = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      result = SignalProcessor.execute_signal_for_state_machine(state, signal)

      assert {:ok, new_state, _result} = result
      # The current_signal should be set during processing (it may get cleared afterward)
      # Let's just verify that the result is successful and the state is updated
      # Agent state should have changed
      assert new_state.agent != state.agent
    end

    test "executes command signals", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "cmd.state", data: nil})

      result = SignalProcessor.execute_signal_for_state_machine(state, signal)

      assert {:ok, _new_state, _result} = result
    end

    test "executes event signals", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "event.test", data: %{message: "test"}})

      result = SignalProcessor.execute_signal_for_state_machine(state, signal)

      assert {:ok, _new_state, %{event_processed: "event.test"}} = result
    end

    test "handles unknown signal types", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "unknown.type", data: nil})

      # This should go through the router, which may return an error
      result = SignalProcessor.execute_signal_for_state_machine(state, signal)

      assert {:error, %{message: "No matching handlers found for signal"}} = result
    end
  end

  describe "execute_instruction_signal/2" do
    test "executes valid instruction", %{state: state} do
      instruction = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      result = SignalProcessor.execute_instruction_signal(state, signal)

      assert {:ok, new_state, _result} = result
      # Agent state should have changed
      assert new_state.agent != state.agent
    end

    test "handles invalid instruction data", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "instruction", data: "invalid"})

      result = SignalProcessor.execute_instruction_signal(state, signal)

      assert {:error, :invalid_instruction_data} = result
    end

    test "handles instruction execution errors", %{state: state} do
      # Create an instruction with non-existent action
      instruction = Instruction.new!(%{action: NonExistentAction, params: %{}})
      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      result = SignalProcessor.execute_instruction_signal(state, signal)

      assert {:error, _reason} = result
    end
  end

  describe "execute_command_signal/2" do
    test "handles cmd.state signal", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "cmd.state", data: nil})

      result = SignalProcessor.execute_command_signal(state, signal)

      assert {:ok, ^state, ^state} = result
    end

    test "handles cmd.queue_size signal", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "cmd.queue_size", data: nil})

      result = SignalProcessor.execute_command_signal(state, signal)

      assert {:ok, ^state, %{queue_size: 0}} = result
    end

    test "handles unknown command", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "cmd.unknown", data: nil})

      result = SignalProcessor.execute_command_signal(state, signal)

      assert {:error, :unknown_command} = result
    end
  end

  describe "execute_event_signal/2" do
    test "processes event signal", %{state: state} do
      {:ok, signal} = Signal.new(%{type: "event.test", data: %{message: "test"}})

      result = SignalProcessor.execute_event_signal(state, signal)

      assert {:ok, ^state, %{event_processed: "event.test"}} = result
    end
  end

  describe "execute_routed_instructions/3" do
    test "executes all routed instructions", %{state: state} do
      instruction1 = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{id: 1}})
      instruction2 = Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{id: 2}})

      {:ok, original_signal} = Signal.new(%{type: "custom", data: nil})

      result =
        SignalProcessor.execute_routed_instructions(
          state,
          [instruction1, instruction2],
          original_signal
        )

      assert {:ok, new_state, _result} = result
      # Agent state should have changed
      assert new_state.agent != state.agent
    end
  end

  describe "edge cases and error handling" do
    test "handles malformed signals gracefully", %{state: state} do
      # Create a signal with completely invalid structure
      malformed_signal = %{invalid: "structure"}

      # This should handle the error gracefully and not crash
      result = SignalProcessor.execute_signal_for_state_machine(state, malformed_signal)

      assert {:error, _reason} = result
    end

    test "processes signals with large payloads", %{state: state} do
      # Create instruction with large data payload
      large_params = for i <- 1..1000, into: %{}, do: {"key_#{i}", "value_#{i}"}

      instruction =
        Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: large_params})

      {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})

      result = SignalProcessor.execute_instruction_signal(state, signal)

      assert {:ok, _new_state, _result} = result
    end
  end

  describe "performance and concurrency" do
    test "processes multiple signals efficiently", %{state: state} do
      # Create a large number of signals
      signals =
        for i <- 1..100 do
          instruction =
            Instruction.new!(%{action: JidoTest.TestActions.NoSchema, params: %{index: i}})

          {:ok, signal} = Signal.new(%{type: "instruction", data: instruction})
          signal
        end

      # Enqueue all signals
      state_with_signals =
        Enum.reduce(signals, state, fn signal, acc_state ->
          {:ok, new_state} = ServerState.enqueue(acc_state, signal)
          new_state
        end)

      # Measure processing time
      {time_microseconds, result} =
        :timer.tc(fn ->
          SignalProcessor.process_signal_batch(state_with_signals, 50)
        end)

      assert {:ok, new_state, [], :more_signals} = result
      # 100 - 50 = 50 remaining
      assert :queue.len(new_state.pending_signals) == 50

      # Processing should be reasonably fast (less than 1 second)
      assert time_microseconds < 1_000_000
    end
  end
end
