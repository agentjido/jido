defmodule JidoTest.Workflow.ChainInterruptTest do
  use JidoTest.Case, async: true
  import ExUnit.CaptureLog

  alias Jido.Workflow.Chain
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.Multiply
  alias JidoTest.TestActions.SlowWorkflow

  @moduletag :capture_log

  setup do
    # Ensure info logs are captured
    :ok = Logger.configure(level: :info)
    on_exit(fn -> Logger.configure(level: :warning) end)
    :ok
  end

  describe "chain/3 with interrupt" do
    test "interrupts chain after first workflow" do
      workflows = [Add, SlowWorkflow, Multiply]
      initial_params = %{value: 5, amount: 2}

      # Interrupt after first workflow
      interrupt_after_first = fn ->
        count = Process.get(:workflow_count, 0)
        Process.put(:workflow_count, count + 1)
        count >= 1
      end

      result = Chain.chain(workflows, initial_params, interrupt_check: interrupt_after_first)

      assert {:interrupted, partial_result} = result
      # Add workflow completed
      assert partial_result.value == 7
      refute Map.has_key?(partial_result, :slow_workflow_complete)
    end

    test "completes chain when interrupt check returns false" do
      workflows = [Add, Multiply]
      initial_params = %{value: 5, amount: 2}

      result = Chain.chain(workflows, initial_params, interrupt_check: fn -> false end)

      assert {:ok, final_result} = result
      # Both workflows completed
      assert final_result.value == 14
    end

    test "interrupts immediately if interrupt check starts true" do
      workflows = [Add, Multiply]
      initial_params = %{value: 5, amount: 2}

      result = Chain.chain(workflows, initial_params, interrupt_check: fn -> true end)

      assert {:interrupted, partial_result} = result
      # No workflows completed
      assert partial_result == initial_params
    end

    test "logs interrupt event" do
      workflows = [Add, SlowWorkflow]
      initial_params = %{value: 5, amount: 2}

      log =
        capture_log([level: :info], fn ->
          Chain.chain(workflows, initial_params, interrupt_check: fn -> true end)
        end)

      assert log =~ "Chain interrupted before workflow"
    end

    test "handles async execution with interruption" do
      workflows = [
        JidoTest.TestActions.Add,
        JidoTest.TestActions.DelayAction,
        JidoTest.TestActions.Multiply
      ]

      initial_params = %{value: 5, amount: 2, delay: 100}

      # Use an Agent to control interruption timing
      {:ok, interrupt_agent} = Agent.start_link(fn -> false end)

      interrupt_check = fn -> Agent.get(interrupt_agent, & &1) end

      task =
        Chain.chain(workflows, initial_params,
          async: true,
          interrupt_check: interrupt_check
        )

      # Allow first workflow to complete
      Process.sleep(50)
      Agent.update(interrupt_agent, fn _ -> true end)

      result = Task.await(task)
      Agent.stop(interrupt_agent)

      assert {:interrupted, partial_result} = result
      # Add workflow completed
      assert partial_result.value == 7
    end

    test "preserves error handling when interrupted" do
      workflows = [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.ErrorAction,
        JidoTest.TestActions.BasicAction
      ]

      initial_params = %{value: 5, error_type: :validation}

      log =
        capture_log([level: :warning], fn ->
          result = Chain.chain(workflows, initial_params, interrupt_check: fn -> false end)
          assert {:error, error} = result
          assert error.type == :execution_error
          assert error.message == "Validation error"
        end)

      assert log =~ "Workflow in chain failed"
    end

    test "handles empty workflow list with interrupt check" do
      result = Chain.chain([], %{value: 5}, interrupt_check: fn -> true end)
      assert {:ok, %{value: 5}} = result
    end
  end
end
