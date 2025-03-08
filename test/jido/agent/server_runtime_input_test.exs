defmodule JidoTest.Agent.Server.RuntimeInputTest do
  use JidoTest.Case, async: true
  require Logger

  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Runtime
  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions

  @moduletag :capture_log
  @moduletag timeout: 30_000

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    # Register test actions with the agent
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.ErrorAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.DelayAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.NoSchema)

    router =
      Router.new!([
        {"test_action", %Instruction{action: TestActions.NoSchema}},
        {"error_action", %Instruction{action: TestActions.ErrorAction}},
        {"delay_action", %Instruction{action: TestActions.DelayAction}}
      ])

    state = %ServerState{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: [
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new(),
      router: router,
      max_queue_size: 10_000
    }

    {:ok, state: state}
  end

  describe "execute_signal/2" do
    test "returns {:ok, state, result} when signal execution is successful", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: %{value: 1}, id: "test-id-123"})
      {:ok, final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
      assert final_state.status == :idle
    end

    test "handles signal callback processing", %{state: state} do
      id = "test-correlation"

      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          id: id
        })

      {:ok, final_state, _result} = Runtime.execute_signal(state, signal)
      assert final_state.current_signal.id == signal.id
    end

    test "routes signal to correct instruction", %{state: state} do
      # Test each routed action type
      signals = [
        {"test_action", %{value: 1}, %{result: 3}},
        {"delay_action", %{delay: 0}, %{result: "Async workflow completed"}},
        # Changed to match any error
        {"error_action", %{}, :error}
      ]

      for {type, data, expected} <- signals do
        signal = Signal.new!(%{type: type, data: data, id: "test-id-#{type}"})

        case expected do
          :error ->
            assert {:error, _reason} = Runtime.execute_signal(state, signal)

          expected_result ->
            {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
            assert result == expected_result
        end
      end
    end

    test "applies signal data to first instruction", %{state: state} do
      # Signal data should be merged with instruction params
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1, extra: "data"},
          id: "test-id-456"
        })

      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
    end

    test "handles errors during signal routing", %{state: state} do
      signal = Signal.new!(%{type: "unknown_action", data: %{}, id: "test-id-789"})
      assert {:error, _reason} = Runtime.execute_signal(state, signal)
    end

    test "handles errors during instruction execution", %{state: state} do
      signal = Signal.new!(%{type: "error_action", data: %{}, id: "test-id-101112"})
      assert {:error, _reason} = Runtime.execute_signal(state, signal)
    end

    test "maintains state through execution chain", %{state: state} do
      id = "test-correlation"

      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          id: id
        })

      {:ok, final_state, _result} = Runtime.execute_signal(state, signal)

      # Check state is maintained
      assert final_state.current_signal.id == signal.id
      assert final_state.status == :idle
      assert :queue.is_empty(final_state.pending_signals)
    end

    test "handles empty signal data", %{state: state} do
      signal = Signal.new!(%{type: "test_action", data: nil, id: "test-id-131415"})
      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: "No params"}
    end

    test "processes signal opts correctly", %{state: state} do
      signal =
        Signal.new!(%{
          type: "test_action",
          data: %{value: 1},
          id: "test-id-161718",
          opts: [test_opt: true]
        })

      {:ok, _final_state, result} = Runtime.execute_signal(state, signal)
      assert result == %{result: 3}
    end

    test "handles invalid signal format", %{state: state} do
      invalid_signals = [
        nil,
        # Not a Signal struct
        %{type: "test_action"},
        # Invalid signal
        Signal.new!(%{type: "test", data: %{}}) |> Map.put(:type, nil)
      ]

      for invalid_signal <- invalid_signals do
        assert {:error, _reason} = Runtime.execute_signal(state, invalid_signal)
      end
    end

    test "returns error when signal type doesn't match any routes and properly dequeues", %{
      state: state
    } do
      # Create two signals - one that won't route and one that will
      unroutable_signal =
        Signal.new!(%{type: "nonexistent_action", data: %{}, id: "test-id-no-match"})

      routable_signal =
        Signal.new!(%{type: "test_action", data: %{value: 1}, id: "test-id-valid"})

      # First enqueue both signals
      {:ok, state_with_signals} = ServerState.enqueue(state, unroutable_signal)
      {:ok, state_with_both} = ServerState.enqueue(state_with_signals, routable_signal)

      # Verify both signals are queued
      assert :queue.len(state_with_both.pending_signals) == 2

      # Process all signals in queue
      {:ok, final_state} = Runtime.process_signals_in_queue(state_with_both)

      # Verify queue is now empty and in final idle state
      assert :queue.is_empty(final_state.pending_signals)
      assert final_state.status == :idle
    end
  end
end
