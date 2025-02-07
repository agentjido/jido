defmodule JidoTest.Agent.Server.RuntimeOutputTest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Agent.Server.{Runtime, State}
  alias Jido.{Agent, Instruction}
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions
  alias Jido.Agent.Server.Signal, as: ServerSignal

  @moduletag :capture_log
  @moduletag timeout: 30000
  # Mock the Agent module's run function
  defmodule MockAgent do
    def run(%Agent{} = agent, _opts) do
      case :queue.peek(agent.pending_instructions) do
        :empty ->
          {:ok, agent, []}

        {:value, %Instruction{action: TestActions.ErrorAction}} ->
          {:error, "Test error"}

        _ ->
          {:ok, agent, []}
      end
    end
  end

  setup do
    {:ok, supervisor} = start_supervised(DynamicSupervisor)
    agent = BasicAgent.new("test")

    # Register test actions with the agent
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.ErrorAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.DelayAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.NoSchema)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.MultiDirectiveAction)
    {:ok, agent} = BasicAgent.register_action(agent, TestActions.Add)

    router =
      Router.new!([
        {"test_action", %Instruction{action: TestActions.NoSchema}},
        {"error_action", %Instruction{action: TestActions.ErrorAction}},
        {"delay_action", %Instruction{action: TestActions.DelayAction}},
        {"multi_action", %Instruction{action: TestActions.MultiDirectiveAction}}
      ])

    state = %State{
      agent: agent,
      child_supervisor: supervisor,
      dispatch: [
        {:pid, [target: self(), delivery_mode: :async]}
      ],
      status: :idle,
      pending_signals: :queue.new(),
      router: router,
      max_queue_size: 10000
    }

    {:ok, state: state}
  end

  describe "do_agent_cmd/3" do
    test "executes single instruction and returns result", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}

      assert {:ok, final_state, _result} = Runtime.do_agent_cmd(state, [instruction], [])
      assert final_state.agent.result == %{result: 3}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "executes multiple initial instructions in sequence", %{state: state} do
      instructions = [
        %Instruction{id: "first", action: TestActions.NoSchema, params: %{value: 1}},
        %Instruction{id: "second", action: TestActions.Add, params: %{value: 3, amount: 1}}
      ]

      assert {:ok, final_state, _result} = Runtime.do_agent_cmd(state, instructions, [])
      assert final_state.agent.result == %{value: 4}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "executes enqueued actions from directives in initial instruction", %{state: state} do
      # Initial instruction that enqueues more actions via directive
      instruction = %Instruction{
        id: "test",
        action: TestActions.MultiDirectiveAction,
        params: %{type: :agent}
      }

      assert {:ok, final_state, _result} = Runtime.do_agent_cmd(state, [instruction], [])
      assert final_state.agent.result == %{value: 4}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "handles errors in initial instruction", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.ErrorAction}

      assert {:error, _reason} = Runtime.do_agent_cmd(state, [instruction], [])
    end

    test "handles empty instruction list", %{state: state} do
      assert {:ok, final_state, nil} = Runtime.do_agent_cmd(state, [], [])
      assert final_state.agent.result == nil
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "preserves opts through execution", %{state: state} do
      instruction = %Instruction{
        id: "test",
        action: TestActions.NoSchema,
        params: %{value: 1},
        opts: [test_opt: true]
      }

      assert {:ok, final_state, _result} =
               Runtime.do_agent_cmd(state, [instruction], test_opt: true)

      assert final_state.agent.result == %{result: 3}
    end

    test "executes initial instruction with enqueued actions but ignores subsequent signal instructions",
         %{state: state} do
      # Initial instruction that enqueues actions
      first_instruction = %Instruction{
        id: "first",
        action: TestActions.MultiDirectiveAction,
        params: %{type: :agent}
      }

      # Signal instruction that should be ignored
      signal_instruction = %Instruction{
        id: "signal",
        action: TestActions.NoSchema,
        params: %{value: 10}
      }

      # First run the initial instruction
      {:ok, state_after_first, _result} = Runtime.do_agent_cmd(state, [first_instruction], [])

      # Try to run signal instruction - it should be ignored
      {:ok, final_state, _result} =
        Runtime.do_agent_cmd(state_after_first, [signal_instruction], [])

      # Result should be from enqueued actions, not from signal instruction
      assert final_state.agent.result == %{result: 12}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end
  end

  describe "do_agent_run/2" do
    test "returns {:ok, state, result} when no pending instructions", %{state: state} do
      agent = %{state.agent | result: :ok, pending_instructions: :queue.new()}
      state = %{state | agent: agent}
      assert {:ok, _state, :ok} = Runtime.do_agent_run(state, [])
    end

    test "executes pending instructions and returns result", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.NoSchema, params: %{value: 1}}
      queue = :queue.in(instruction, :queue.new())
      agent = %{state.agent | pending_instructions: queue}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{result: 3}} = Runtime.do_agent_run(state, [])
      assert final_state.agent.result == %{result: 3}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "executes enqueued actions from directives", %{state: state} do
      # Create initial instruction that will enqueue more actions
      instruction = %Instruction{
        id: "test",
        action: TestActions.MultiDirectiveAction,
        params: %{
          type: :agent
        }
      }

      queue = :queue.in(instruction, :queue.new())
      agent = %{state.agent | pending_instructions: queue}
      state = %{state | agent: agent}

      {:ok, final_state, _result} = Runtime.do_agent_run(state, [])

      assert final_state.agent.result == %{value: 4}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "handles errors during instruction execution", %{state: state} do
      instruction = %Instruction{id: "test", action: TestActions.ErrorAction}
      queue = :queue.in(instruction, :queue.new())
      agent = %{state.agent | pending_instructions: queue}
      state = %{state | agent: agent}

      assert {:error, _reason} = Runtime.do_agent_run(state, [])
    end

    test "executes chain of enqueued actions", %{state: state} do
      # First action adds 2 to value 1
      first_instruction = %Instruction{
        id: "first",
        action: TestActions.NoSchema,
        params: %{value: 1}
      }

      # Second action adds 1 to the previous result
      second_instruction = %Instruction{
        id: "second",
        action: TestActions.Add,
        params: %{value: 3, amount: 1}
      }

      queue = :queue.in(first_instruction, :queue.new())
      queue = :queue.in(second_instruction, queue)
      agent = %{state.agent | pending_instructions: queue}
      state = %{state | agent: agent}

      assert {:ok, final_state, %{value: 4}} = Runtime.do_agent_run(state, [])
      # First adds 2 (1->3), second adds 1 (3->4)
      assert final_state.agent.result == %{value: 4}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end
  end

  describe "handle_agent_result/3" do
    test "returns {:ok, state} if the command result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      assert {:ok, _state} = Runtime.handle_agent_result(state, agent, [])
    end

    test "emits output with correct correlation and causation IDs", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id, current_signal_type: :async}
      agent = %{state.agent | result: %{value: "test result"}}

      {:ok, _state} = Runtime.handle_agent_result(state, agent, [])

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))
      assert signal.data == %{value: "test result"}
      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "handle_agent_instruction_result/3" do
    test "returns {:ok, state} if the agent instruction result is successful", %{state: state} do
      assert {:ok, _updated_state} = Runtime.handle_agent_instruction_result(state, :ok, [])
    end

    test "emits output with correct correlation and causation IDs", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id, current_signal_type: :async}
      result = %{value: "test result"}

      {:ok, _state} = Runtime.handle_agent_instruction_result(state, result, [])

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))
      assert signal.data == %{value: "test result"}
      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "handle_signal_result/3" do
    test "returns {:ok, state, result} if the agent result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      state = %{state | agent: agent}

      signal = Signal.new!(%{type: "test", data: %{value: "test result"}})

      assert {:ok, new_state, result} =
               Runtime.handle_signal_result(state, signal, %{value: "test result"})

      assert new_state.status == :idle
      assert result == %{value: "test result"}
    end

    test "preserves correlation ID through execution", %{state: state} do
      correlation_id = "test-correlation-id"
      state = %{state | current_correlation_id: correlation_id, current_signal_type: :async}
      agent = %{state.agent | result: %{value: "test result"}}
      state = %{state | agent: agent}

      signal = Signal.new!(%{type: "test", data: %{value: "test result"}})

      {:ok, _new_state, _result} =
        Runtime.handle_signal_result(state, signal, %{value: "test result"})

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))
      assert signal.data == %{value: "test result"}
      assert signal.jido_correlation_id == correlation_id
    end
  end

  describe "apply_signal_to_first_instruction/2" do
    test "merges signal data into first instruction params" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: %{baz: "qux"}})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{foo: "bar", baz: "qux"}
    end

    test "handles nil params in instruction" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: nil})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{foo: "bar"}
    end

    test "handles nil data in signal" do
      signal = Signal.new!(%{type: "test", data: nil})
      instruction = Instruction.new!(%{action: TestActions.NoSchema, params: %{baz: "qux"}})

      assert {:ok, [result | _]} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])

      assert result.params == %{baz: "qux"}
    end

    test "returns ok with empty list for empty instructions" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      assert {:ok, []} = Runtime.apply_signal_to_first_instruction(signal, [])
    end

    test "returns error for invalid instruction" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      assert {:error, :invalid_instruction} =
               Runtime.apply_signal_to_first_instruction(signal, [:not_an_instruction])
    end

    test "returns error if merging params fails" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}})

      instruction = :not_an_instruction

      assert {:error, :invalid_instruction} =
               Runtime.apply_signal_to_first_instruction(signal, [instruction])
    end
  end
end
