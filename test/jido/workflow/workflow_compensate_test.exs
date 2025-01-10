defmodule JidoTest.WorkflowCompensateTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias Jido.Error
  alias Jido.Workflow
  alias JidoTest.TestActions.CompensateAction

  @moduletag :capture_log

  setup do
    # Ensure debug logs are captured
    :ok = Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: :warning) end)
    :ok
  end

  describe "do_run with compensation" do
    test "triggers compensation on action failure" do
      params = %{
        test_value: "test",
        should_fail: true,
        compensation_should_fail: false,
        delay: 10
      }

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 50, backoff: 25)

      assert error.type == :compensation_error
      assert error.message =~ "Compensation completed for: Intentional failure"
      assert error.details.compensated == true
      assert error.details.original_error.message == "Intentional failure"
      assert is_map(error.details)
    end

    test "handles failed compensation" do
      params = %{should_fail: true, compensation_should_fail: true}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.type == :compensation_error
      assert error.message =~ "Compensation failed for: Intentional failure"
      assert error.details.compensated == false
      assert error.details.original_error.message == "Intentional failure"
      assert error.details.compensation_error.message == "Compensation failed"
    end

    test "preserves context in compensation" do
      params = %{should_fail: true}
      context = %{test_id: "123"}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, context, timeout: 100, backoff: 25)

      assert error.details.compensation_context.test_id == "123"
    end

    test "preserves original params in compensation" do
      params = %{should_fail: true, test_value: "preserved"}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.details.test_value == "preserved"
    end

    test "compensation respects delay" do
      params = %{should_fail: true, delay: 25}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.details.compensated == true
    end
  end

  describe "timeout behavior with compensation" do
    test "times out during long compensation using action metadata timeout" do
      # Use a delay longer than the 50ms timeout defined in the CompensateAction
      params = %{should_fail: true, compensation_should_fail: false, delay: 100}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 50, backoff: 25)

      assert error.type == :compensation_error
      assert error.message =~ "Compensation failed for: Intentional failure"
      assert error.details.compensation_error =~ "Compensation timed out after 50ms"
      assert error.details.compensated == false
    end

    test "completes compensation within timeout" do
      params = %{should_fail: true, delay: 10}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.type == :compensation_error
      assert error.details.compensated == true
    end
  end

  describe "telemetry with compensation" do
    test "emits telemetry events for compensation flow" do
      params = %{should_fail: true}

      log =
        capture_log(fn ->
          assert {:error, %Error{} = error} =
                   Workflow.run(CompensateAction, params, %{},
                     telemetry: :full,
                     timeout: 100,
                     backoff: 25
                   )

          assert error.details.compensated == true
        end)

      assert log =~ "Action Elixir.JidoTest.TestActions.CompensateAction start"
      assert log =~ "Action Elixir.JidoTest.TestActions.CompensateAction error"
    end
  end

  describe "retry behavior with compensation" do
    test "attempts compensation after all retries are exhausted" do
      params = %{should_fail: true}

      assert {:error, %Error{} = error} =
               Workflow.run(CompensateAction, params, %{},
                 max_retries: 2,
                 backoff: 10,
                 timeout: 100
               )

      assert error.type == :compensation_error
      assert error.details.compensated == true
      assert error.details.original_error.message == "Intentional failure"
    end

    test "doesn't attempt compensation if retry succeeds" do
      params = %{should_fail: false}

      assert {:ok, result} =
               Workflow.run(CompensateAction, params, %{},
                 max_retries: 2,
                 backoff: 10,
                 timeout: 100
               )

      assert result.result == "CompensateAction completed"
    end
  end
end
