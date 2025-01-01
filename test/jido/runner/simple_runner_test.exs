defmodule Jido.Runner.SimpleTest do
  use ExUnit.Case, async: true
  alias Jido.Runner.Simple
  alias Jido.Instruction
  alias Jido.Runner.Result
  alias Jido.Agent.Directive.EnqueueDirective
  alias JidoTest.TestActions.{Add, ErrorAction}
  alias Jido.Actions.Syscall
  alias Jido.Agent.Syscall.{SpawnSyscall, KillSyscall, BroadcastSyscall}

  @moduletag :capture_log

  describe "run/2" do
    test "executes single instruction successfully" do
      instruction = %Instruction{
        action: Add,
        params: %{value: 0, amount: 1},
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{value: 0},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 0},
                instructions: [^instruction],
                result_state: %{value: 1},
                status: :ok,
                error: nil
              }} = Simple.run(agent)
    end

    test "handles instruction execution error" do
      instruction = %Instruction{
        action: ErrorAction,
        params: %{error_type: :validation},
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:error, result} = Simple.run(agent)
      assert result.error.message == "Validation error"
    end

    test "returns ok when no pending instructions" do
      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.new()
      }

      assert {:ok, %Result{status: :ok}} = Simple.run(agent)
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

      agent = %{
        id: "test-agent",
        state: %{value: 0},
        pending_instructions: :queue.from_list([instruction1, instruction2])
      }

      assert {:ok,
              %Result{
                initial_state: %{value: 0},
                instructions: [^instruction1],
                result_state: %{value: 1},
                status: :ok,
                pending_instructions: remaining
              }} = Simple.run(agent)

      assert :queue.to_list(remaining) == [instruction2]
    end

    test "handles directive returned from action" do
      instruction = %Instruction{
        action: JidoTest.TestActions.EnqueueAction,
        params: %{
          action: :next_action,
          params: %{}
        },
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok,
              %Result{
                initial_state: %{},
                instructions: [^instruction],
                result_state: %{},
                directives: [%EnqueueDirective{action: :next_action, params: %{}, context: %{}}],
                status: :ok,
                error: nil
              }} = Simple.run(agent)
    end

    test "handles spawn syscall" do
      instruction = %Instruction{
        action: Syscall.Spawn,
        params: %{
          module: TestModule,
          args: [1, 2, 3]
        },
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{processes: []},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok,
              %Result{
                initial_state: %{processes: []},
                instructions: [^instruction],
                result_state: %{processes: []},
                syscalls: [%SpawnSyscall{module: TestModule, args: [1, 2, 3]}],
                status: :ok
              }} = Simple.run(agent)
    end

    test "handles kill syscall" do
      pid = spawn(fn -> :ok end)

      instruction = %Instruction{
        action: Syscall.Kill,
        params: %{pid: pid},
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{processes: [pid]},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok,
              %Result{
                initial_state: %{processes: [^pid]},
                instructions: [^instruction],
                result_state: %{processes: [^pid]},
                syscalls: [%KillSyscall{pid: ^pid}],
                status: :ok
              }} = Simple.run(agent)
    end

    test "handles broadcast syscall" do
      instruction = %Instruction{
        action: Syscall.Broadcast,
        params: %{
          topic: "test_topic",
          message: "hello world"
        },
        context: %{}
      }

      agent = %{
        id: "test-agent",
        state: %{},
        pending_instructions: :queue.from_list([instruction])
      }

      assert {:ok,
              %Result{
                initial_state: %{},
                instructions: [^instruction],
                result_state: %{},
                syscalls: [%BroadcastSyscall{topic: "test_topic", message: "hello world"}],
                status: :ok
              }} = Simple.run(agent)
    end
  end
end
