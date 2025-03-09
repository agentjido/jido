defmodule Jido.Runner.SimpleTest do
  use JidoTest.Case, async: true
  alias Jido.Runner.Simple
  alias Jido.Instruction
  alias JidoTest.TestActions.{Add, ErrorAction, CompensateAction}
  alias JidoTest.TestAgents.FullFeaturedAgent

  @moduletag :capture_log

  describe "run/2" do
    test "executes single instruction successfully" do
      instruction = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent.result == %{value: 1}
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "executes only first instruction with three in queue" do
      instruction1 = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      instruction2 = %Instruction{
        action: Add,
        params: %{value: 1, amount: 2},
        context: %{}
      }

      instruction3 = %Instruction{
        action: Add,
        params: %{value: 3, amount: 3},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | pending_instructions: :queue.from_list([instruction1, instruction2, instruction3])
      }

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      # First instruction executed
      assert updated_agent.result == %{value: 1}
      # Two instructions remain
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify remaining instructions in order
      {{:value, next}, queue} = :queue.out(updated_agent.pending_instructions)
      assert next == instruction2

      {{:value, last}, _} = :queue.out(queue)
      assert last == instruction3
    end

    test "handles instruction execution error" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :validation},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Validation error"
    end

    test "returns unchanged agent when no pending instructions" do
      agent = FullFeaturedAgent.new("test-agent")
      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent == agent
    end

    test "executes only first instruction and preserves remaining in queue" do
      instruction1 = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      instruction2 = %Instruction{
        action: Add,
        params: %{value: 1, amount: 1},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction1, instruction2])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent.result == %{value: 1}
      assert :queue.len(updated_agent.pending_instructions) == 1

      # Verify remaining instruction
      {{:value, remaining}, _} = :queue.out(updated_agent.pending_instructions)
      assert remaining == instruction2
    end

    test "handles directive returned from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          action: :next_action,
          params: %{}
        },
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Simple.run(agent)
      assert updated_agent.result == %{}
      # The enqueue directive adds a new instruction to the queue
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, next_instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert next_instruction.action == :next_action
      assert next_instruction.params == %{}
    end

    test "handles invalid directive returned from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          # Invalid - action is required
          action: nil,
          params: %{}
        },
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, %Jido.Error{} = error} = Simple.run(agent)
      assert error.type == :validation_error
      assert error.message == "Invalid directive"
    end

    test "handles multiple directives from action" do
      # Two Server directives
      instruction = %Instruction{
        action: JidoTest.TestActions.MultiDirectiveAction,
        params: %{type: :server},
        context: %{},
        opts: [timeout: 0]
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, directives} = Simple.run(agent)
      assert length(directives) == 2
      assert :queue.is_empty(updated_agent.pending_instructions)

      # Verify directives
      [first, second] = directives
      assert first.module == JidoTest.TestActions.MultiDirectiveAction
      assert first.args == []
      assert is_pid(second.pid)
    end

    test "handles runtime errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :runtime},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Runtime error"
    end

    test "handles argument errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :argument},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Argument error in JidoTest.TestActions.ErrorAction: Argument error"
    end

    test "handles compensation in action execution" do
      instruction = %Instruction{
        action: CompensateAction,
        params: %{
          should_fail: true,
          compensation_should_fail: false,
          test_value: "test"
        },
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Compensation completed for: Intentional failure"
    end

    test "preserves agent state on error" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :runtime},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | state: Map.put(agent.state, :value, 42),
          pending_instructions: :queue.from_list([instruction])
      }

      initial_state = agent.state

      assert {:error, _} = Simple.run(agent)
      assert agent.state == initial_state
    end

    test "handles custom errors in action execution" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :custom},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:error, error} = Simple.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Custom error"
    end

    test "injects agent state into instruction context" do
      instruction = %Instruction{
        action: JidoTest.TestActions.StateCheckAction,
        params: %{},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")

      agent = %{
        agent
        | state: %{value: 42, status: :ready},
          pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok, updated_agent, []} = Simple.run(agent)
      # StateCheckAction verifies state is in context and returns it
      assert updated_agent.result == %{
               state_in_context: %{value: 42, status: :ready}
             }
    end

    test "respects apply_directives? option when false" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          action: :next_action,
          params: %{value: 42}
        },
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent, directives} = Simple.run(agent, apply_directives?: false)
      # Verify directives were returned but not applied
      assert length(directives) == 1
      [directive] = directives
      assert %Jido.Agent.Directive.Enqueue{} = directive
      assert directive.action == :next_action
      assert directive.params == %{value: 42}
      # Verify no instructions were enqueued
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "respects apply_directives? option when true (default)" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          action: :next_action,
          params: %{value: 42}
        },
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, updated_agent, []} = Simple.run(agent)
      # Verify directive was applied (instruction was enqueued)
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 42}
    end
  end
end
