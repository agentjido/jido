defmodule JidoTest.Agent.ServerEnqueueDirectiveTest do
  use JidoTest.Case, async: true
  use Mimic

  alias Jido.Agent.Server
  alias Jido.Agent.Server.State, as: ServerState
  alias Jido.Agent.Server.Directive
  alias JidoTest.TestAgents.{BasicAgent, LoopingAgent}

  alias JidoTest.TestActions.{
    BasicAction,
    EnqueueAction,
    LoopingAction,
    Add,
    Multiply,
    CountdownAction,
    IncrementWithLimit
  }

  alias Jido.Actions.{Iterator, While}

  setup :verify_on_exit!
  @moduletag :capture_log

  setup do
    # Start a unique test registry for each test
    registry_name = :"TestRegistry_#{System.unique_integer([:positive, :monotonic])}"
    {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)

    %{registry: registry_name}
  end

  describe "EnqueueAction via server directive tests" do
    setup do
      {:ok, supervisor} = start_supervised(DynamicSupervisor)
      agent = BasicAgent.new("test-agent")

      state = %ServerState{
        agent: agent,
        child_supervisor: supervisor,
        dispatch: [{:pid, [target: self(), delivery_mode: :async]}],
        status: :idle,
        pending_signals: :queue.new()
      }

      {:ok, state: state}
    end

    test "successfully creates enqueue signal via directive execution", %{state: state} do
      enqueue_directive = %Jido.Agent.Directive.Enqueue{
        action: BasicAction,
        params: %{value: 42}
      }

      {:ok, new_state} = Directive.execute(state, enqueue_directive)

      # Verify signal was enqueued in server's signal queue (not agent queue yet)
      assert {:value, signal} = :queue.peek(new_state.pending_signals)
      assert signal.type == "jido.agent.cmd.enqueue"
      assert %Jido.Instruction{action: BasicAction, params: %{value: 42}} = signal.data
    end

    test "maintains signal queue order with multiple enqueues", %{state: state} do
      first_directive = %Jido.Agent.Directive.Enqueue{
        action: BasicAction,
        params: %{value: 1}
      }

      second_directive = %Jido.Agent.Directive.Enqueue{
        action: BasicAction,
        params: %{value: 2}
      }

      # Execute first directive
      {:ok, state_after_first} = Directive.execute(state, first_directive)

      # Execute second directive  
      {:ok, final_state} = Directive.execute(state_after_first, second_directive)

      # Verify signal queue order (newest at front since enqueue_front is used)
      {{:value, first_signal}, queue} = :queue.out(final_state.pending_signals)
      {{:value, second_signal}, _} = :queue.out(queue)

      # second one enqueued first
      assert first_signal.data.params.value == 2
      # first one pushed back
      assert second_signal.data.params.value == 1
    end
  end

  describe "EnqueueAction via GenServer integration tests" do
    setup %{registry: registry} do
      agent_id = "test-agent-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Server.start_link(
          agent: BasicAgent.new(agent_id),
          registry: registry,
          id: agent_id
        )

      {:ok, pid: pid, agent_id: agent_id}
    end

    test "successfully executes enqueued action through server", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: EnqueueAction,
          params: %{
            action: BasicAction,
            params: %{value: 42}
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # EnqueueAction returns empty map
      assert result == %{}

      # The enqueued action should have been executed immediately
      # We can verify server is still responsive
      {:ok, state} = Server.state(pid)
      assert state.status == :idle

      # The pending instructions queue should be empty since all were executed
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "executes multiple enqueued actions in sequence", %{pid: pid} do
      first_instruction =
        Jido.Instruction.new!(
          action: EnqueueAction,
          params: %{
            action: BasicAction,
            params: %{value: 1}
          }
        )

      second_instruction =
        Jido.Instruction.new!(
          action: EnqueueAction,
          params: %{
            action: BasicAction,
            params: %{value: 2}
          }
        )

      # Execute both instructions - each should trigger its own enqueued action
      {:ok, result1} = Server.call(pid, first_instruction)
      {:ok, result2} = Server.call(pid, second_instruction)

      assert result1 == %{}
      assert result2 == %{}

      # Verify server processed everything and is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "handles multiple concurrent enqueue requests", %{pid: pid} do
      # Create multiple instructions to enqueue concurrently
      instructions =
        for i <- 1..5 do
          Jido.Instruction.new!(
            action: EnqueueAction,
            params: %{
              action: BasicAction,
              params: %{value: i}
            }
          )
        end

      # Execute them concurrently using cast (fire and forget)
      tasks =
        Enum.map(instructions, fn instruction ->
          Task.async(fn -> Server.call(pid, instruction) end)
        end)

      # Wait for all to complete
      results = Task.await_many(tasks)

      # All should return empty maps
      assert Enum.all?(results, fn {:ok, result} -> result == %{} end)

      # Verify server processed everything
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "enqueued actions execute after the enqueueing action completes", %{pid: pid} do
      # This test verifies the execution order behavior
      instruction =
        Jido.Instruction.new!(
          action: EnqueueAction,
          params: %{
            action: BasicAction,
            params: %{value: 42}
          }
        )

      {:ok, result} = Server.call(pid, instruction)
      assert result == %{}

      # Server should be idle after processing
      {:ok, state} = Server.state(pid)
      assert state.status == :idle

      # Make another call to verify server remains responsive
      regular_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 999})
      {:ok, regular_result} = Server.call(pid, regular_instruction)
      assert regular_result == %{value: 999}
    end

    test "server remains responsive after multiple enqueue operations", %{pid: pid} do
      # Enqueue multiple actions in sequence
      for i <- 1..10 do
        instruction =
          Jido.Instruction.new!(
            action: EnqueueAction,
            params: %{
              action: BasicAction,
              params: %{value: i}
            }
          )

        {:ok, result} = Server.call(pid, instruction)
        assert result == %{}
      end

      # Verify server is still responsive and all actions were processed
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)

      # Verify we can still make regular calls
      regular_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 999})
      {:ok, result} = Server.call(pid, regular_instruction)
      assert result == %{value: 999}
    end
  end

  describe "LoopingAction tests - demonstrating cascaded enqueuing" do
    setup %{registry: registry} do
      agent_id = "loop-agent-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Server.start_link(
          agent: LoopingAgent.new(agent_id),
          registry: registry,
          id: agent_id
        )

      {:ok, pid: pid, agent_id: agent_id}
    end

    test "single instruction triggers 10 action executions", %{pid: pid} do
      # Start the loop with counter=10, expecting 10 total action executions
      instruction =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 10, value: 0}
        )

      {:ok, result} = Server.call(pid, instruction)

      # First iteration result
      assert result.iteration == 10
      assert result.accumulated_value == 10
      refute Map.has_key?(result, :final)

      # Give the server time to process all enqueued actions
      Process.sleep(100)

      # Verify server processed everything and is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)

      # Verify server remains responsive after the loop
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 42})
      {:ok, test_result} = Server.call(pid, test_instruction)
      assert test_result == %{value: 42}
    end

    test "smaller loop with counter=3 executes correctly", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 3, value: 0}
        )

      {:ok, result} = Server.call(pid, instruction)

      # First iteration: counter=3, value=0+3=3
      assert result.iteration == 3
      assert result.accumulated_value == 3
      refute Map.has_key?(result, :final)

      # Allow processing time
      Process.sleep(50)

      # Verify server is idle after processing loop
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "concurrent looping actions don't interfere", %{pid: pid} do
      # Start two different looping sequences concurrently
      instruction1 =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 3, value: 100}
        )

      instruction2 =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 2, value: 200}
        )

      # Execute both concurrently
      task1 = Task.async(fn -> Server.call(pid, instruction1) end)
      task2 = Task.async(fn -> Server.call(pid, instruction2) end)

      results = Task.await_many([task1, task2])

      # Both should succeed with their first iteration results
      assert match?(
               [
                 {:ok, %{iteration: 3, accumulated_value: 103}},
                 {:ok, %{iteration: 2, accumulated_value: 202}}
               ],
               results
             ) or
               match?(
                 [
                   {:ok, %{iteration: 2, accumulated_value: 202}},
                   {:ok, %{iteration: 3, accumulated_value: 103}}
                 ],
                 results
               )

      # Allow all enqueued actions to complete
      Process.sleep(100)

      # Verify server is idle after all loops complete
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "looping action with counter=1 executes once without enqueuing", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 1, value: 50}
        )

      {:ok, result} = Server.call(pid, instruction)

      # Single iteration with final=true
      assert result.iteration == 1
      assert result.accumulated_value == 51
      assert result.final == true

      # No additional processing time needed since nothing was enqueued
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "looping action mixed with regular actions", %{pid: pid} do
      # Start a loop
      loop_instruction =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 5, value: 0}
        )

      {:ok, loop_result} = Server.call(pid, loop_instruction)
      assert loop_result.iteration == 5
      assert loop_result.accumulated_value == 5

      # Execute a regular action while loop is processing
      basic_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 999})
      {:ok, basic_result} = Server.call(pid, basic_instruction)
      assert basic_result == %{value: 999}

      # Allow loop to complete
      Process.sleep(100)

      # Execute another regular action
      final_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 777})
      {:ok, final_result} = Server.call(pid, final_instruction)
      assert final_result == %{value: 777}

      # Verify server is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "handles invalid counter gracefully", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: LoopingAction,
          params: %{counter: 0, value: 10}
        )

      {:error, _reason} = Server.call(pid, instruction)

      # Server should remain responsive after error
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 42})
      {:ok, result} = Server.call(pid, test_instruction)
      assert result == %{value: 42}
    end
  end

  describe "Iterator tests - wrapping actions for repeated execution" do
    setup %{registry: registry} do
      agent_id = "iterator-agent-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Server.start_link(
          agent: LoopingAgent.new(agent_id),
          registry: registry,
          id: agent_id
        )

      {:ok, pid: pid, agent_id: agent_id}
    end

    test "executes wrapped Add action 5 times", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Add,
            count: 5,
            params: %{value: 10, amount: 2}
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # First iteration result from Iterator itself
      assert result.index == 1
      assert result.count == 5
      assert result.action == Add
      assert result.params == %{value: 10, amount: 2}
      assert result.final == false

      # Allow all enqueued actions to complete
      Process.sleep(150)

      # Verify server processed everything and is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)

      # Verify server remains responsive
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 42})
      {:ok, test_result} = Server.call(pid, test_instruction)
      assert test_result == %{value: 42}
    end

    test "executes wrapped Multiply action 3 times", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Multiply,
            count: 3,
            params: %{value: 5, amount: 3}
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      assert result.index == 1
      assert result.count == 3
      assert result.action == Multiply
      assert result.params == %{value: 5, amount: 3}

      # Allow processing time
      Process.sleep(100)

      # Verify server is idle after processing
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "single iteration executes once with final=true", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Add,
            count: 1,
            params: %{value: 100, amount: 5}
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # Single iteration with final=true
      assert result.index == 1
      assert result.count == 1
      assert result.action == Add
      assert result.final == true

      # Allow the final target action to execute
      Process.sleep(50)

      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "concurrent iterator actions don't interfere", %{pid: pid} do
      instruction1 =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Add,
            count: 3,
            params: %{value: 10, amount: 1}
          }
        )

      instruction2 =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Multiply,
            count: 2,
            params: %{value: 4, amount: 2}
          }
        )

      # Execute both concurrently
      task1 = Task.async(fn -> Server.call(pid, instruction1) end)
      task2 = Task.async(fn -> Server.call(pid, instruction2) end)

      results = Task.await_many([task1, task2])

      # Both should succeed with their first iteration results
      assert length(results) == 2

      assert Enum.all?(results, fn {:ok, result} ->
               result.index == 1 and
                 is_atom(result.action) and
                 is_integer(result.count)
             end)

      # Allow all enqueued actions to complete
      Process.sleep(150)

      # Verify server is idle after all iterations complete
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "iterator with BasicAction executes correctly", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: BasicAction,
            count: 4,
            params: %{value: 777}
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      assert result.index == 1
      assert result.count == 4
      assert result.action == BasicAction
      assert result.params == %{value: 777}

      # Allow processing time for all iterations
      Process.sleep(120)

      # Verify server processed everything
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "mixed iterator and regular actions", %{pid: pid} do
      # Start an iterator
      iterator_instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Add,
            count: 3,
            params: %{value: 50, amount: 10}
          }
        )

      {:ok, iterator_result} = Server.call(pid, iterator_instruction)
      assert iterator_result.index == 1
      assert iterator_result.action == Add

      # Execute a regular action while iterator is processing
      basic_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 888})
      {:ok, basic_result} = Server.call(pid, basic_instruction)
      assert basic_result == %{value: 888}

      # Allow iterator to complete
      Process.sleep(120)

      # Execute another regular action
      final_instruction = Jido.Instruction.new!(action: Multiply, params: %{value: 3, amount: 7})
      {:ok, final_result} = Server.call(pid, final_instruction)
      assert final_result == %{value: 21}

      # Verify server is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "handles invalid count gracefully", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: Iterator,
          params: %{
            action: Add,
            count: 0,
            params: %{value: 10, amount: 2}
          }
        )

      {:error, _reason} = Server.call(pid, instruction)

      # Server should remain responsive after error
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 42})
      {:ok, result} = Server.call(pid, test_instruction)
      assert result == %{value: 42}
    end
  end

  describe "While loop tests - conditional execution with body actions" do
    setup %{registry: registry} do
      agent_id = "while-agent-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Server.start_link(
          agent: LoopingAgent.new(agent_id),
          registry: registry,
          id: agent_id
        )

      {:ok, pid: pid, agent_id: agent_id}
    end

    test "countdown while loop executes until counter reaches 0", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: CountdownAction,
            params: %{counter: 5, continue: true},
            condition_field: :continue,
            max_iterations: 10
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # First iteration should show continue = true
      assert result.iteration == 1
      assert result.body == CountdownAction
      assert result.condition_field == :continue
      assert result.continue == true
      refute Map.has_key?(result, :final)

      # Allow all iterations to complete
      Process.sleep(200)

      # Verify server processed everything and is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)

      # Verify server remains responsive
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 99})
      {:ok, test_result} = Server.call(pid, test_instruction)
      assert test_result == %{value: 99}
    end

    test "increment while loop with limit stops at boundary", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: IncrementWithLimit,
            params: %{value: 0, increment: 2, limit: 8, continue: true},
            condition_field: :continue,
            max_iterations: 20
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      assert result.iteration == 1
      assert result.body == IncrementWithLimit
      assert result.continue == true

      # Allow processing time
      Process.sleep(150)

      # Verify server is idle after processing
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "while loop with false initial condition exits immediately", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: CountdownAction,
            # Initial condition is false
            params: %{counter: 0, continue: false},
            condition_field: :continue,
            max_iterations: 10
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # Should exit immediately with final=true
      assert result.iteration == 1
      assert result.body == CountdownAction
      assert result.continue == false
      assert result.final == true

      # No additional processing time needed
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "concurrent while loops don't interfere", %{pid: pid} do
      instruction1 =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: CountdownAction,
            params: %{counter: 3, continue: true},
            condition_field: :continue,
            max_iterations: 10
          }
        )

      instruction2 =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: IncrementWithLimit,
            params: %{value: 0, increment: 3, limit: 9, continue: true},
            condition_field: :continue,
            max_iterations: 10
          }
        )

      # Execute both concurrently
      task1 = Task.async(fn -> Server.call(pid, instruction1) end)
      task2 = Task.async(fn -> Server.call(pid, instruction2) end)

      results = Task.await_many([task1, task2])

      # Both should succeed with their first iteration results
      assert length(results) == 2

      assert Enum.all?(results, fn {:ok, result} ->
               result.iteration == 1 and
                 is_atom(result.body) and
                 result.continue == true
             end)

      # Allow all loops to complete
      Process.sleep(200)

      # Verify server is idle after all loops complete
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "while loop with custom condition field", %{pid: pid} do
      # Using a different condition field name
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: IncrementWithLimit,
            params: %{value: 0, increment: 1, limit: 3, active: true},
            # Different field name
            condition_field: :active,
            max_iterations: 10
          }
        )

      # This should exit immediately since :active field doesn't get updated
      {:ok, result} = Server.call(pid, instruction)

      assert result.iteration == 1
      assert result.body == IncrementWithLimit
      assert result.condition_field == :active
      # Based on :active field
      assert result.continue == true

      # Allow some processing time
      Process.sleep(100)

      {:ok, state} = Server.state(pid)
      assert state.status == :idle
    end

    test "while loop mixed with other actions", %{pid: pid} do
      # Start a while loop
      while_instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: CountdownAction,
            params: %{counter: 4, continue: true},
            condition_field: :continue,
            max_iterations: 10
          }
        )

      {:ok, while_result} = Server.call(pid, while_instruction)
      assert while_result.iteration == 1
      assert while_result.body == CountdownAction

      # Execute a regular action while loop is processing
      basic_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 777})
      {:ok, basic_result} = Server.call(pid, basic_instruction)
      assert basic_result == %{value: 777}

      # Allow while loop to complete
      Process.sleep(150)

      # Execute another regular action
      final_instruction = Jido.Instruction.new!(action: Add, params: %{value: 5, amount: 3})
      {:ok, final_result} = Server.call(pid, final_instruction)
      assert final_result == %{value: 8}

      # Verify server is idle
      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end

    test "while loop respects max_iterations limit", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: IncrementWithLimit,
            # Would run 100 times
            params: %{value: 0, increment: 1, limit: 100, continue: true},
            condition_field: :continue,
            # But limited to 3
            max_iterations: 3
          }
        )

      {:ok, result} = Server.call(pid, instruction)
      assert result.continue == true

      # Allow some processing, but it should hit the limit
      Process.sleep(100)

      # Server should handle the limit and remain responsive
      {:ok, state} = Server.state(pid)
      assert state.status == :idle

      # Should still be able to execute other actions
      test_instruction = Jido.Instruction.new!(action: BasicAction, params: %{value: 42})
      {:ok, test_result} = Server.call(pid, test_instruction)
      assert test_result == %{value: 42}
    end

    test "while loop handles missing condition field gracefully", %{pid: pid} do
      instruction =
        Jido.Instruction.new!(
          action: While,
          params: %{
            body: BasicAction,
            # No continue field
            params: %{value: 42},
            condition_field: :continue,
            max_iterations: 5
          }
        )

      {:ok, result} = Server.call(pid, instruction)

      # Should exit immediately since condition field is missing (falsy)
      assert result.iteration == 1
      assert result.body == BasicAction
      assert result.continue == false
      assert result.final == true

      {:ok, state} = Server.state(pid)
      assert state.status == :idle
      assert :queue.is_empty(state.agent.pending_instructions)
    end
  end
end
