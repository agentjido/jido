defmodule JidoTest.Workflow.ActionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Error
  alias Jido.Action
  alias JidoTest.TestActions.Add
  alias JidoTest.TestActions.CompensateAction
  alias JidoTest.TestActions.ConcurrentAction
  alias JidoTest.TestActions.Divide
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.FullAction
  alias JidoTest.TestActions.LongRunningAction
  alias JidoTest.TestActions.Multiply
  alias JidoTest.TestActions.NoSchema
  alias JidoTest.TestActions.RateLimitedAction
  alias JidoTest.TestActions.StreamingAction
  alias JidoTest.TestActions.Subtract

  require OK

  @moduletag :capture_log

  describe "error formatting" do
    test "format_config_error formats NimbleOptions.ValidationError" do
      error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is invalid"}
      formatted = Error.format_nimble_config_error(error, "Action", __MODULE__)

      assert formatted ==
               "Invalid configuration given to use Jido.Action (#{__MODULE__}) for key [:name]: is invalid"
    end

    test "format_config_error formats NimbleOptions.ValidationError with empty keys_path" do
      error = %NimbleOptions.ValidationError{keys_path: [], message: "is invalid"}
      formatted = Error.format_nimble_config_error(error, "Action", __MODULE__)

      assert formatted ==
               "Invalid configuration given to use Jido.Action (#{__MODULE__}): is invalid"
    end

    test "format_config_error handles binary errors" do
      assert Error.format_nimble_config_error("Some error", "Action", __MODULE__) == "Some error"
    end

    test "format_config_error handles other error types" do
      assert Error.format_nimble_config_error(:some_atom, "Action", __MODULE__) ==
               ":some_atom"
    end

    test "format_nimble_validation_error formats NimbleOptions.ValidationError" do
      error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      formatted = Error.format_nimble_validation_error(error, "Action", __MODULE__)
      assert formatted == "Invalid parameters for Action (#{__MODULE__}) at [:input]: is required"
    end

    test "format_nimble_validation_error formats NimbleOptions.ValidationError with empty keys_path" do
      error = %NimbleOptions.ValidationError{keys_path: [], message: "is invalid"}
      formatted = Error.format_nimble_validation_error(error, "Action", __MODULE__)
      assert formatted == "Invalid parameters for Action (#{__MODULE__}): is invalid"
    end

    test "format_nimble_validation_error handles binary errors" do
      assert Error.format_nimble_validation_error("Some error", "Action", __MODULE__) ==
               "Some error"
    end

    test "format_nimble_validation_error handles other error types" do
      assert Error.format_nimble_validation_error(:some_atom, "Action", __MODULE__) ==
               ":some_atom"
    end
  end

  describe "action creation and metadata" do
    test "creates a valid action with all options" do
      assert FullAction.name() == "full_action"
      assert FullAction.description() == "A full action for testing"
      assert FullAction.category() == "test"
      assert FullAction.tags() == ["test", "full"]
      assert FullAction.vsn() == "1.0.0"

      assert FullAction.schema() == [
               a: [type: :integer, required: true],
               b: [type: :integer, required: true]
             ]
    end

    test "creates a valid action with no schema" do
      assert NoSchema.name() == "add_two"
      assert NoSchema.description() == "Adds 2 to the input value"
      assert NoSchema.schema() == []
    end

    test "to_json returns correct representation" do
      json = FullAction.to_json()
      assert json.name == "full_action"
      assert json.description == "A full action for testing"
      assert json.category == "test"
      assert json.tags == ["test", "full"]
      assert json.vsn == "1.0.0"

      assert json.schema == [
               a: [type: :integer, required: true],
               b: [type: :integer, required: true]
             ]
    end

    test "schema validation covers all types" do
      valid_params = %{a: 42, b: 2}

      assert {:ok, validated} = FullAction.validate_params(valid_params)
      assert validated.a == 42
      assert validated.b == 2

      invalid_params = %{a: "not an integer", b: 2}

      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullAction.validate_params(invalid_params)

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end
  end

  describe "action execution" do
    test "executes a valid action successfully" do
      assert {:ok, result} = FullAction.run(%{a: 5, b: 2}, %{})
      assert result.a == 5
      assert result.b == 2
      assert result.result == 7
    end

    test "executes basic calculator actions" do
      assert {:ok, %{value: 6}} = Add.run(%{value: 5, amount: 1}, %{})
      assert {:ok, %{value: 10}} = Multiply.run(%{value: 5, amount: 2}, %{})
      assert {:ok, %{value: 3}} = Subtract.run(%{value: 5, amount: 2}, %{})
      assert {:ok, %{value: 2.5}} = Divide.run(%{value: 5, amount: 2}, %{})
    end

    test "handles division by zero" do
      assert_raise RuntimeError, "Cannot divide by zero", fn ->
        Divide.run(%{value: 5, amount: 0}, %{})
      end
    end

    test "handles different error scenarios" do
      assert {:error, "Validation error"} =
               ErrorAction.run(%{error_type: :validation}, %{})

      assert_raise RuntimeError, "Runtime error", fn ->
        ErrorAction.run(%{error_type: :runtime}, %{})
      end
    end
  end

  describe "parameter validation" do
    test "validates required parameters" do
      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullAction.validate_params(%{})

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end

    test "validates parameter types" do
      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullAction.validate_params(%{a: "not an integer", b: 2})

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end
  end

  describe "error handling" do
    test "new returns an error tuple" do
      assert {:error, %Error{type: :config_error, message: error_message}} = Action.new()
      assert error_message =~ "Actions should not be defined at runtime"
    end
  end

  describe "property-based tests" do
    property "valid action always returns a result for valid input" do
      check all(
              a <- integer(),
              b <- integer(1..1000)
            ) do
        params = %{a: a, b: b}
        assert {:ok, result} = FullAction.run(params, %{})
        assert result.a == a
        assert result.b == b
        assert result.result == a + b
      end
    end
  end

  describe "edge cases" do
    test "handles very large numbers in calculator workflows" do
      large_number = 1_000_000_000_000_000_000_000
      assert {:ok, result} = Add.run(%{value: large_number, amount: 1}, %{})
      assert result.value == large_number + 1
    end
  end

  describe "advanced actions" do
    test "long running action" do
      assert {:ok, "Workflow completed"} = LongRunningAction.run(%{}, %{})
    end

    test "rate limited action" do
      Enum.each(1..5, fn _ ->
        assert {:ok, _} = RateLimitedAction.run(%{workflow: "test"}, %{})
      end)

      assert {:error, "Rate limit exceeded. Please try again later."} =
               RateLimitedAction.run(%{workflow: "test"}, %{})
    end

    test "streaming action" do
      assert {:ok, %{stream: stream}} =
               StreamingAction.run(%{chunk_size: 2, total_items: 10}, %{})

      assert Enum.to_list(stream) == [3, 7, 11, 15, 19]
    end

    test "concurrent action" do
      assert {:ok, %{results: results}} = ConcurrentAction.run(%{inputs: [1, 2, 3, 4, 5]}, %{})
      assert length(results) == 5
      assert Enum.all?(results, fn r -> r in [2, 4, 6, 8, 10] end)
    end
  end

  describe "compensation configuration" do
    test "creates action with compensation config" do
      assert Enum.sort(CompensateAction.__action_metadata__()[:compensation]) == [
               enabled: true,
               max_retries: 3,
               timeout: 50
             ]
    end

    test "defaults to disabled compensation" do
      assert Enum.sort(NoSchema.__action_metadata__()[:compensation]) == [
               enabled: false,
               max_retries: 1,
               timeout: 5000
             ]
    end
  end

  describe "compensation callbacks" do
    test "successful execution doesn't trigger compensation" do
      params = %{should_fail: false, compensation_should_fail: false, delay: 0}
      assert {:ok, result} = CompensateAction.run(params, %{})
      assert result.result == "CompensateAction completed"
    end

    test "failed execution can be compensated" do
      assert {:error, error} =
               CompensateAction.run(%{should_fail: true, compensation_should_fail: false}, %{
                 test_context: true
               })

      assert {:ok, compensation_result} =
               CompensateAction.on_error(
                 %{should_fail: true, compensation_should_fail: false, delay: 0},
                 error,
                 %{test_context: true},
                 []
               )

      assert compensation_result.compensated == true
      assert compensation_result.original_error == error
      assert compensation_result.compensation_context.test_context == true
    end

    test "compensation can fail" do
      assert {:error, error} =
               CompensateAction.run(%{should_fail: true, compensation_should_fail: true}, %{})

      assert {:error, compensation_error} =
               CompensateAction.on_error(
                 %{should_fail: true, compensation_should_fail: true, delay: 0},
                 error,
                 %{},
                 []
               )

      assert compensation_error.message =~ "Compensation failed"
    end

    test "compensation receives original params and error" do
      params = %{should_fail: true, test_value: 123, compensation_should_fail: false, delay: 0}
      assert {:error, original_error} = CompensateAction.run(params, %{})

      assert {:ok, compensation_result} =
               CompensateAction.on_error(params, original_error, %{}, [])

      assert compensation_result.test_value == 123
      assert compensation_result.original_error == original_error
    end

    test "compensation with delay respects timeout" do
      params = %{should_fail: true, delay: 100, compensation_should_fail: false}
      assert {:error, error} = CompensateAction.run(params, %{})

      assert {:ok, compensation_result} =
               CompensateAction.on_error(
                 params,
                 error,
                 %{},
                 timeout: 200
               )

      assert compensation_result.compensated == true
    end
  end
end
