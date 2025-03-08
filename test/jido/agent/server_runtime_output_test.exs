defmodule JidoTest.Agent.Server.RuntimeOutputTest do
  use JidoTest.Case, async: true
  require Logger

  alias Jido.Agent.Server.{Runtime, State}
  alias Jido.Instruction
  alias Jido.Signal
  alias Jido.Signal.Router
  alias JidoTest.TestAgents.BasicAgent
  alias JidoTest.TestActions
  alias Jido.Agent.Server.Signal, as: ServerSignal

  @moduletag :capture_log
  @moduletag timeout: 30_000

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
      max_queue_size: 10_000
    }

    {:ok, state: state}
  end

  describe "do_agent_cmd/3" do
    test "executes single instruction and returns result", %{state: state} do
      instruction = %Instruction{action: TestActions.NoSchema, params: %{value: 1}}

      assert {:ok, final_state, result} = Runtime.do_agent_cmd(state, [instruction], [])
      assert final_state.agent.result == %{result: 3}
      assert result == %{result: 3}
      assert :queue.is_empty(final_state.agent.pending_instructions)
    end

    test "executes enqueued actions from directives in initial instruction", %{state: state} do
      # Initial instruction that enqueues more actions via directive
      instruction = %Instruction{
        id: "test",
        action: TestActions.MultiDirectiveAction,
        params: %{type: :agent}
      }

      assert {:ok, step_state, _result} = Runtime.do_agent_cmd(state, [instruction], [])
      assert step_state.agent.result == %{}
      assert :queue.len(step_state.pending_signals) == 2
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
      assert :queue.len(final_state.pending_signals) == 2
    end
  end

  describe "handle_agent_result/3" do
    test "returns {:ok, state} if the command result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      assert {:ok, _state} = Runtime.handle_agent_result(state, agent, [])
    end

    test "handle_agent_result/3 emits output with correct correlation and causation IDs", %{
      state: state
    } do
      id = "test-correlation-id"

      signal =
        Signal.new!(%{
          type: "test",
          data: %{value: "test result"},
          id: id
        })

      state = %{state | current_signal: signal, current_signal_type: :async}
      agent = %{state.agent | result: %{value: "test result"}}

      {:ok, _state} = Runtime.handle_agent_result(state, agent, [])

      assert_receive {:signal, signal}, 500
      assert signal.source == id
    end
  end

  describe "handle_agent_instruction_result/3" do
    test "returns {:ok, state} if the agent instruction result is successful", %{state: state} do
      assert {:ok, _updated_state} = Runtime.handle_agent_instruction_result(state, :ok, [])
    end

    test "handle_agent_instruction_result/3 emits output with correct correlation and causation IDs",
         %{state: state} do
      id = "test-correlation-id"

      signal =
        Signal.new!(%{
          type: "test",
          data: %{value: "test result"},
          id: id
        })

      state = %{state | current_signal: signal, current_signal_type: :async}
      result = %{value: "test result"}

      {:ok, _state} = Runtime.handle_agent_instruction_result(state, result, [])

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :instruction_result}))
      assert signal.data == %{value: "test result"}
      assert signal.source == id
    end
  end

  describe "handle_signal_result/3" do
    test "returns {:ok, state, result} if the agent result is successful", %{state: state} do
      agent = %{state.agent | result: :ok}
      state = %{state | agent: agent}

      signal = Signal.new!(%{type: "test", data: %{value: "test result"}, id: "test-id-123"})

      assert {:ok, new_state, result} =
               Runtime.handle_signal_result(state, signal, %{value: "test result"})

      assert new_state.status == :idle
      assert result == %{value: "test result"}
    end

    test "handle_signal_result/3 preserves correlation ID through execution", %{state: state} do
      id = "test-correlation-id"

      signal =
        Signal.new!(%{
          type: "test",
          data: %{value: "test result"},
          id: id
        })

      state = %{state | current_signal: signal, current_signal_type: :async}
      agent = %{state.agent | result: %{value: "test result"}}
      state = %{state | agent: agent}

      {:ok, _new_state, _result} =
        Runtime.handle_signal_result(state, signal, %{value: "test result"})

      assert_receive {:signal, signal}
      assert signal.type == ServerSignal.join_type(ServerSignal.type({:out, :signal_result}))
      assert signal.data == %{value: "test result"}
      assert signal.source == id
    end
  end

  describe "apply_signal_to_first_instruction/2" do
    test "merges signal data into first instruction params" do
      signal = Signal.new!(%{type: "test", data: %{foo: "bar"}, id: "test-id-456"})
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
