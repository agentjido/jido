defmodule JidoTest.WorkflowRunTest do
  use JidoTest.Case, async: false
  use Mimic

  import ExUnit.CaptureLog
  import ExUnit.CaptureIO

  alias Jido.Error
  alias Jido.Workflow
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.IOAction
  alias JidoTest.TestActions.RetryAction

  @attempts_table :workflow_run_test_attempts

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    original_level = Logger.level()
    Logger.configure(level: :debug)

    :ets.new(@attempts_table, [:set, :public, :named_table])
    :ets.insert(@attempts_table, {:attempts, 0})

    on_exit(fn ->
      Logger.configure(level: original_level)

      if :ets.info(@attempts_table) != :undefined do
        :ets.delete(@attempts_table)
      end
    end)

    {:ok, attempts_table: @attempts_table}
  end

  describe "run/4" do
    test "executes action successfully" do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} = Workflow.run(BasicAction, %{value: 5})
        end)

      assert log =~ "Action Elixir.JidoTest.TestActions.BasicAction start"
      assert log =~ "Action Elixir.JidoTest.TestActions.BasicAction complete"
      verify!()
    end

    test "handles successful 3-item tuple with directive" do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{}, %Jido.Agent.Directive.Enqueue{}} =
                   Workflow.run(Jido.Actions.Directives.EnqueueAction, %{
                     action: BasicAction,
                     params: %{value: 5}
                   })
        end)

      assert log =~ "Action Elixir.Jido.Actions.Directives.EnqueueAction start"
      assert log =~ "Action Elixir.Jido.Actions.Directives.EnqueueAction complete"
      verify!()
    end

    test "handles error 3-item tuple with directive" do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:error, %Error{}, %Jido.Agent.Directive.Enqueue{}} =
                   Workflow.run(JidoTest.TestActions.ErrorDirective, %{
                     action: BasicAction,
                     params: %{value: 5}
                   })
        end)

      assert log =~ "Action Elixir.JidoTest.TestActions.ErrorDirective start"
      assert log =~ "Action Elixir.JidoTest.TestActions.ErrorDirective error"
      verify!()
    end

    test "handles action error" do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 2, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:error, %Error{}} = Workflow.run(ErrorAction, %{}, %{}, timeout: 50)
        end)

      assert log =~ "Action Elixir.JidoTest.TestActions.ErrorAction start"
      assert log =~ "Action Elixir.JidoTest.TestActions.ErrorAction error"
      verify!()
    end

    test "retries on error and then succeeds", %{attempts_table: attempts_table} do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 3, fn _, _, _ -> :ok end)

      capture_log(fn ->
        result =
          Workflow.run(
            RetryAction,
            %{max_attempts: 3, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:ok, %{result: "success after 3 attempts"}} = result
        assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
      end)

      verify!()
    end

    test "fails after max retries", %{attempts_table: attempts_table} do
      expect(System, :monotonic_time, fn :microsecond -> 0 end)
      expect(:telemetry, :execute, 3, fn _, _, _ -> :ok end)

      capture_log(fn ->
        result =
          Workflow.run(
            RetryAction,
            %{max_attempts: 5, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:error, %Error{}} = result
        assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
      end)

      verify!()
    end

    test "handles invalid params" do
      assert {:error, %Error{}} = Workflow.run(BasicAction, %{invalid: "params"})
    end

    test "handles timeout" do
      capture_log(fn ->
        assert {:error, %Error{message: message}} =
                 Workflow.run(DelayAction, %{delay: 1000}, %{}, timeout: 50)

        assert message =~ "timed out after 50ms. This could be due"
      end)
    end

    test "handles IO operations" do
      io =
        capture_io(fn ->
          assert {:ok, %{input: "test", operation: :inspect}} =
                   Workflow.run(IOAction, %{input: "test", operation: :inspect}, %{},
                     timeout: 5000
                   )
        end)

      assert io =~ "IOAction"
      assert io =~ "input"
      assert io =~ "test"
      assert io =~ "operation"
      assert io =~ "inspect"
    end
  end

  describe "normalize_params/1" do
    test "normalizes a map" do
      params = %{key: "value"}
      assert {:ok, ^params} = Workflow.normalize_params(params)
    end

    test "normalizes a keyword list" do
      params = [key: "value"]
      assert {:ok, %{key: "value"}} = Workflow.normalize_params(params)
    end

    test "normalizes {:ok, map}" do
      params = {:ok, %{key: "value"}}
      assert {:ok, %{key: "value"}} = Workflow.normalize_params(params)
    end

    test "normalizes {:ok, keyword list}" do
      params = {:ok, [key: "value"]}
      assert {:ok, %{key: "value"}} = Workflow.normalize_params(params)
    end

    test "handles {:error, reason}" do
      params = {:error, "some error"}

      assert {:error, %Error{type: :validation_error, message: "some error"}} =
               Workflow.normalize_params(params)
    end

    test "passes through %Error{} with different types" do
      errors = [
        %Error{type: :validation_error, message: "validation failed"},
        %Error{type: :execution_error, message: "execution failed"},
        %Error{type: :timeout_error, message: "workflow timed out"}
      ]

      for error <- errors do
        assert {:error, ^error} = Workflow.normalize_params(error)
      end
    end

    test "returns error for invalid params" do
      params = "invalid"

      assert {:error, %Error{type: :validation_error, message: "Invalid params type: " <> _}} =
               Workflow.normalize_params(params)
    end
  end

  describe "normalize_context/1" do
    test "normalizes a map" do
      context = %{key: "value"}
      assert {:ok, ^context} = Workflow.normalize_context(context)
    end

    test "normalizes a keyword list" do
      context = [key: "value"]
      assert {:ok, %{key: "value"}} = Workflow.normalize_context(context)
    end

    test "returns error for invalid context" do
      context = "invalid"

      assert {:error, %Error{type: :validation_error, message: "Invalid context type: " <> _}} =
               Workflow.normalize_context(context)
    end
  end

  describe "validate_action/1" do
    defmodule NotAAction do
      @moduledoc false
      def validate_params(_), do: :ok
    end

    test "returns :ok for valid action" do
      assert :ok = Workflow.validate_action(BasicAction)
    end

    test "returns error for action without run/2" do
      assert {:error,
              %Error{
                type: :invalid_action,
                message:
                  "Module JidoTest.WorkflowRunTest.NotAAction is not a valid action: missing run/2 function"
              }} = Workflow.validate_action(NotAAction)
    end
  end

  describe "validate_params/2" do
    test "returns validated params for valid params" do
      assert {:ok, %{value: 5}} = Workflow.validate_params(BasicAction, %{value: 5})
    end

    test "returns error for invalid params" do
      {:error, %Error{type: :validation_error, message: error_message}} =
        Workflow.validate_params(BasicAction, %{invalid: "params"})

      assert error_message =~
               "Invalid parameters for Action (Elixir.JidoTest.TestActions.BasicAction)"

      assert error_message =~ "required :value option not found"
    end
  end
end
