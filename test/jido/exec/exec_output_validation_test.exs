defmodule JidoTest.Exec.OutputValidationTest do
  use JidoTest.Case, async: true

  alias Jido.Exec
  alias Jido.Error
  alias JidoTest.TestActions.OutputSchemaAction
  alias JidoTest.TestActions.InvalidOutputAction
  alias JidoTest.TestActions.NoOutputSchemaAction
  alias JidoTest.TestActions.OutputCallbackAction

  @moduletag :capture_log

  describe "output validation integration with Exec" do
    test "successful action with valid output" do
      params = %{input: "hello"}
      context = %{}

      assert {:ok, result} = Exec.run(OutputSchemaAction, params, context)
      assert result.result == "HELLO"
      assert result.length == 5
      assert result.extra == "not validated"
    end

    test "action with invalid output fails execution" do
      params = %{}
      context = %{}

      assert {:error, %Error{type: :validation_error, message: error_message}} =
               Exec.run(InvalidOutputAction, params, context)

      assert error_message =~ "required :required_field option not found"
    end

    test "action without output schema succeeds without validation" do
      params = %{}
      context = %{}

      assert {:ok, result} = Exec.run(NoOutputSchemaAction, params, context)
      assert result.anything == "goes"
      assert result.here == 123
    end

    test "output validation with callbacks" do
      params = %{input: 42}
      context = %{}

      assert {:ok, result} = Exec.run(OutputCallbackAction, params, context)
      assert result.value == 42
      assert result.preprocessed == true
      assert result.postprocessed == true
    end

    test "output validation with async execution" do
      params = %{input: "world"}

      async_ref = Exec.run_async(OutputSchemaAction, params, %{})
      assert {:ok, result} = Exec.await(async_ref)

      assert result.result == "WORLD"
      assert result.length == 5
      assert result.extra == "not validated"
    end

    test "async execution with invalid output fails" do
      async_ref = Exec.run_async(InvalidOutputAction, %{}, %{})

      assert {:error, %Error{type: :validation_error, message: error_message}} =
               Exec.await(async_ref)

      assert error_message =~ "required :required_field option not found"
    end

    test "output validation works with action returning tuple with directive" do
      # We need to create a test action that returns {:ok, result, directive}
      defmodule TupleOutputAction do
        use Jido.Action,
          name: "tuple_output_action",
          output_schema: [
            status: [type: :string, required: true]
          ]

        def run(_params, _context) do
          {:ok, %{status: "success", extra: "data"}, :continue}
        end
      end

      assert {:ok, result, directive} = Exec.run(TupleOutputAction, %{}, %{})
      assert result.status == "success"
      assert result.extra == "data"
      assert directive == :continue
    end

    test "output validation fails with tuple return format" do
      defmodule InvalidTupleOutputAction do
        use Jido.Action,
          name: "invalid_tuple_output_action",
          output_schema: [
            required_field: [type: :string, required: true]
          ]

        def run(_params, _context) do
          {:ok, %{wrong_field: "value"}, :continue}
        end
      end

      assert {:error, %Error{type: :validation_error}, directive} =
               Exec.run(InvalidTupleOutputAction, %{}, %{})

      assert directive == :continue
    end

    test "output validation preserves unknown fields" do
      params = %{input: "test"}

      assert {:ok, result} = Exec.run(OutputSchemaAction, params, %{})

      # Known fields are validated
      assert result.result == "TEST"
      assert result.length == 4

      # Unknown fields are preserved
      assert result.extra == "not validated"
    end
  end

  describe "output validation error handling" do
    test "output validation errors are properly formatted" do
      defmodule TypeErrorOutputAction do
        use Jido.Action,
          name: "type_error_output_action",
          output_schema: [
            count: [type: :integer, required: true]
          ]

        def run(_params, _context) do
          {:ok, %{count: "not an integer"}}
        end
      end

      assert {:error, %Error{type: :validation_error, message: error_message}} =
               Exec.run(TypeErrorOutputAction, %{}, %{})

      assert error_message =~ "Action output"
      assert error_message =~ "count"
    end

    test "output validation callback errors are handled" do
      defmodule CallbackErrorOutputAction do
        use Jido.Action,
          name: "callback_error_output_action",
          output_schema: [
            value: [type: :string, required: true]
          ]

        def run(_params, _context) do
          {:ok, %{value: "test"}}
        end

        def on_before_validate_output(_output) do
          {:error, Error.validation_error("Callback failed")}
        end
      end

      assert {:error, %Error{type: :validation_error, message: "Callback failed"}} =
               Exec.run(CallbackErrorOutputAction, %{}, %{})
    end
  end
end
