defmodule Jido.Runner.ChainTest do
  use ExUnit.Case, async: true
  alias Jido.Runner.Chain
  alias Jido.Instruction
  alias Jido.Runner.Result
  alias Jido.Error
  alias JidoTest.TestActions.{Add, Multiply, ErrorAction, EnqueueAction}
  alias Jido.Agent.Directive.EnqueueDirective
  alias Jido.Actions.Syscall
  alias Jido.Agent.Syscall.{SpawnSyscall, KillSyscall, BroadcastSyscall}

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

      agent = %{
        id: "test-agent",
        state: %{value: 0},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 0},
                instructions: ^instructions,
                result_state: %{value: 4},
                status: :ok
              }} = Chain.run(agent)
    end

    test "returns ok when no pending instructions" do
      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.new()
      }

      assert {:ok, %Result{status: :ok}} = Chain.run(agent)
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

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:error,
              %Result{
                initial_state: %{},
                instructions: ^instructions,
                error: %Error{message: "Validation error"},
                status: :error
              }} = Chain.run(agent)
    end

    test "handles single directive returned from action" do
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

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{},
                instructions: ^instructions,
                result_state: %{},
                directives: [
                  %EnqueueDirective{
                    action: :next_action,
                    params: %{value: 1},
                    context: %{}
                  }
                ],
                status: :ok
              }} = Chain.run(agent)
    end

    test "handles multiple directives from chain of actions" do
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

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{},
                instructions: ^instructions,
                result_state: %{},
                directives: [
                  %EnqueueDirective{
                    action: :first_action,
                    params: %{value: 1},
                    context: %{}
                  },
                  %EnqueueDirective{
                    action: :second_action,
                    params: %{value: 2},
                    context: %{}
                  }
                ],
                status: :ok
              }} = Chain.run(agent, continue_on_directive: true)
    end

    test "handles mix of state changes and directives in chain" do
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
            params: %{value: 1}
          },
          context: %{}
        }
      ]

      agent = %{
        id: "test-agent",
        state: %{value: 0},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 0},
                instructions: ^instructions,
                result_state: %{value: 1},
                directives: [
                  %EnqueueDirective{
                    action: :next_action,
                    params: %{value: 1},
                    context: %{}
                  }
                ],
                status: :ok
              }} = Chain.run(agent)
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

      agent = %{
        id: "test-agent",
        state: %{value: 10},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 10},
                instructions: ^instructions,
                result_state: %{value: 30},
                status: :ok
              }} = Chain.run(agent)
    end

    test "accumulates syscalls through chain" do
      instructions = [
        %Instruction{
          action: Syscall.Spawn,
          params: %{
            module: TestModule,
            args: [1, 2, 3]
          },
          context: %{}
        },
        %Instruction{
          action: Syscall.Broadcast,
          params: %{
            topic: "test_topic",
            message: "hello world"
          },
          context: %{}
        }
      ]

      agent = %{
        id: "test-agent",
        state: %{processes: []},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{processes: []},
                instructions: ^instructions,
                result_state: %{processes: []},
                syscalls: [
                  %SpawnSyscall{module: TestModule, args: [1, 2, 3]},
                  %BroadcastSyscall{topic: "test_topic", message: "hello world"}
                ],
                status: :ok
              }} = Chain.run(agent)
    end

    test "accumulates syscalls and state changes" do
      pid = spawn(fn -> :ok end)

      instructions = [
        %Instruction{
          action: Add,
          params: %{value: 0, amount: 1},
          context: %{}
        },
        %Instruction{
          action: Syscall.Kill,
          params: %{pid: pid},
          context: %{}
        }
      ]

      agent = %{
        id: "test-agent",
        state: %{value: 0, processes: [pid]},
        pending_instructions: :queue.from_list(instructions)
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 0, processes: [^pid]},
                instructions: ^instructions,
                result_state: %{value: 1, processes: [^pid]},
                syscalls: [%KillSyscall{pid: ^pid}],
                status: :ok
              }} = Chain.run(agent)
    end
  end
end
