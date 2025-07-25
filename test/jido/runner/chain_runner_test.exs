defmodule Jido.Runner.ChainTest do
  use JidoTest.Case, async: true
  alias Jido.Runner.Chain
  alias Jido.Instruction
  alias JidoTest.TestActions.{Add, Multiply, ErrorAction, EnqueueAction, CompensateAction}
  alias JidoTest.TestAgents.FullFeaturedAgent

  @moduletag :capture_log

  describe "run/2" do
    test "executes instructions in sequence and returns final result" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 2, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert updated_agent.result == %{value: 4}
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "executes all initial instructions but accumulates directive instructions in queue" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 42}
          },
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      # Verify final result
      assert updated_agent.result == %{value: 3}

      # Verify directive's instruction was enqueued but not executed
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 42}
    end

    test "returns unchanged agent when no pending instructions" do
      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | result: :ok}
      assert {:ok, ^agent, []} = Chain.run(agent)
    end

    test "propagates errors from actions" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :validation},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Validation error"
    end

    test "accumulates directives in queue from single action" do
      instructions = [
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 1}
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 1}
    end

    test "accumulates multiple directives in queue from chain of actions" do
      instructions = [
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :first_action,
            params: %{value: 1}
          },
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :second_action,
            params: %{value: 2}
          },
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify enqueued instructions
      {{:value, first}, queue} = :queue.out(updated_agent.pending_instructions)
      assert first.action == :first_action
      assert first.params == %{value: 1}

      {{:value, second}, _} = :queue.out(queue)
      assert second.action == :second_action
      assert second.params == %{value: 2}
    end

    test "accumulates results through Add, Multiply, Add chain" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 10, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Multiply,
          params: %{value: 11, amount: 2},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 22, amount: 8},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert updated_agent.result == %{value: 30}
      assert :queue.is_empty(updated_agent.pending_instructions)
    end

    test "handles runtime errors in action execution" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :runtime},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Server error in JidoTest.TestActions.ErrorAction: Runtime error"
    end

    test "handles argument errors in action execution" do
      instructions = [
        %Instruction{
          action: ErrorAction,
          params: %{error_type: :argument},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message == "Argument error in JidoTest.TestActions.ErrorAction: Argument error"
    end

    test "handles compensation in action execution" do
      instructions = [
        %Instruction{
          action: CompensateAction,
          params: %{
            should_fail: true,
            compensation_should_fail: false,
            test_value: "test"
          },
          context: %{}
        }
      ]

      agent = JidoTest.TestAgents.ErrorHandlingAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:error, error} = Chain.run(agent)
      assert error.message =~ "Compensation completed for:"
      assert error.details.compensated == true
      assert Exception.message(error.details.original_error) =~ "Intentional failure"
    end

    test "respects apply_directives? option when false" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 42}
          },
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, directives} = Chain.run(agent, apply_directives?: false)
      # Verify final result
      assert updated_agent.result == %{value: 3}
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
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: EnqueueAction,
          params: %{
            action: :next_action,
            params: %{value: 42}
          },
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      # Verify final result
      assert updated_agent.result == %{value: 3}
      # Verify directive was applied (instruction was enqueued)
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, enqueued}, _} = :queue.out(updated_agent.pending_instructions)
      assert enqueued.action == :next_action
      assert enqueued.params == %{value: 42}
    end
  end

  describe "instruction directive handling" do
    test "handles single instruction returned as directive" do
      instruction = %Instruction{
        action: JidoTest.TestActions.ReturnInstructionAction,
        params: %{},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Chain.run(agent)
      assert updated_agent.result == %{}
      # The returned instruction should be added to the queue
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, next_instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert next_instruction.action == JidoTest.TestActions.ReturnInstructionAction
      assert next_instruction.params == %{value: 42}
    end

    test "handles list of instructions returned as directive" do
      instruction = %Instruction{
        action: JidoTest.TestActions.ReturnInstructionListAction,
        params: %{},
        context: %{}
      }

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list([instruction])}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Chain.run(agent)
      assert updated_agent.result == %{}
      # Both returned instructions should be added to the queue
      assert :queue.len(updated_agent.pending_instructions) == 2

      # Verify first instruction
      {{:value, first}, queue} = :queue.out(updated_agent.pending_instructions)
      assert first.action == JidoTest.TestActions.ReturnInstructionAction
      assert first.params == %{value: 1}

      # Verify second instruction
      {{:value, second}, _} = :queue.out(queue)
      assert second.action == JidoTest.TestActions.ReturnInstructionAction
      assert second.params == %{value: 2}
    end

    test "handles mixed instructions and results in chain" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: JidoTest.TestActions.ReturnInstructionAction,
          params: %{},
          context: %{}
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 2},
          context: %{}
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, %FullFeaturedAgent{} = updated_agent, []} = Chain.run(agent)
      # Final result from Add actions
      assert updated_agent.result == %{value: 3}
      # Instruction from ReturnInstructionAction added to queue
      assert :queue.len(updated_agent.pending_instructions) == 1
      {{:value, next_instruction}, _} = :queue.out(updated_agent.pending_instructions)
      assert next_instruction.action == JidoTest.TestActions.ReturnInstructionAction
      assert next_instruction.params == %{value: 42}
    end
  end

  describe "timeout option handling" do
    test "merges runner timeout with instruction opts (instruction opts take precedence)" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{},
          # Instruction-specific timeout
          opts: [timeout: 5000]
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{},
          # No timeout in this instruction
          opts: []
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      # Runner provides a different timeout, but instruction timeout should win for first instruction
      assert {:ok, updated_agent, []} = Chain.run(agent, timeout: 1000)
      assert updated_agent.result == %{value: 2}
    end

    test "uses runner timeout when instruction has no timeout" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{},
          # No timeout in instruction
          opts: []
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{},
          # No timeout in instruction
          opts: []
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      # Runner timeout should be used for all instructions
      assert {:ok, updated_agent, []} = Chain.run(agent, timeout: 1000)
      assert updated_agent.result == %{value: 2}
    end

    test "merges all opts correctly in chain" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{},
          # Instruction has some opts
          opts: [timeout: 5000, retry: true]
        },
        %Instruction{
          action: Add,
          params: %{value: 1, amount: 1},
          context: %{},
          # Different timeout
          opts: [timeout: 2000]
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      # Runner provides different opts, should be merged with instruction opts taking precedence
      assert {:ok, updated_agent, []} =
               Chain.run(agent, timeout: 1000, log_level: :debug, apply_directives?: false)

      assert updated_agent.result == %{value: 2}
      # Each instruction should have received merged opts with instruction opts taking precedence
    end

    test "works with timeout 0 (no timeout)" do
      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{},
          # Disable timeout for this instruction
          opts: [timeout: 0]
        }
      ]

      agent = FullFeaturedAgent.new("test-agent")
      agent = %{agent | pending_instructions: :queue.from_list(instructions)}

      assert {:ok, updated_agent, []} = Chain.run(agent)
      assert updated_agent.result == %{value: 1}
    end
  end
end
