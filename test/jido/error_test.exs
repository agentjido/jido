defmodule JidoTest.ErrorTest do
  use JidoTest.Case, async: true

  alias Jido.Error

  describe "error type functions" do
    test "create specific error types" do
      # Test validation errors
      error = Error.validation_error("Test message")
      assert %Error.InvalidInputError{} = error
      assert error.message == "Test message"
      assert error.details == %{}

      # Test execution errors  
      error = Error.execution_error("Test message")
      assert %Error.ExecutionFailureError{} = error
      assert error.message == "Test message"

      # Test timeout errors
      error = Error.timeout_error("Test message")
      assert %Error.TimeoutError{} = error
      assert error.message == "Test message"

      # Test config errors
      error = Error.config_error("Test message")
      assert %Error.ConfigurationError{} = error
      assert error.message == "Test message"

      # Test internal errors
      error = Error.internal_error("Test message")
      assert %Error.InternalError{} = error
      assert error.message == "Test message"
    end

    test "create errors with details" do
      details = %{reason: "test"}

      error = Error.validation_error("Test message", details)
      assert error.details == details

      error = Error.execution_error("Test message", details)
      assert error.details == details

      error = Error.timeout_error("Test message", details)
      assert error.details == details
    end

    test "legacy compatibility functions work" do
      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :action_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message"])
        assert Exception.exception?(error)
        assert Exception.message(error) == "Test message"
      end
    end
  end

  describe "specific error types" do
    test "InvalidActionError includes action field" do
      error = Error.invalid_action("Bad action", %{action: MyAction})
      assert %Error.InvalidActionError{} = error
      assert error.action == MyAction
    end

    test "InvalidSensorError includes sensor field" do
      error = Error.invalid_sensor("Bad sensor", %{sensor: MySensor})
      assert %Error.InvalidSensorError{} = error
      assert error.sensor == MySensor
    end

    test "TimeoutError includes timeout field" do
      error = Error.timeout_error("Timed out", %{timeout: 5000})
      assert %Error.TimeoutError{} = error
      assert error.timeout == 5000
    end

    test "RoutingError includes target field" do
      error = Error.routing_error("No route", %{target: "unknown"})
      assert %Error.RoutingError{} = error
      assert error.target == "unknown"
    end
  end

  describe "compensation_error/2" do
    test "creates compensation error with original error" do
      original = Error.execution_error("Original error")

      error =
        Error.compensation_error(original, %{
          compensated: true,
          compensation_result: %{refund_id: "ref_123"}
        })

      assert %Error.CompensationError{} = error
      assert error.original_error == original
      assert error.compensated == true
      assert error.compensation_result == %{refund_id: "ref_123"}
      assert error.message == "Compensation completed for: Original error"
    end

    test "handles failed compensation" do
      original = Error.execution_error("Payment failed")

      error =
        Error.compensation_error(original, %{
          compensated: false,
          compensation_error: "Refund failed"
        })

      assert %Error.CompensationError{} = error
      assert error.original_error == original
      assert error.compensated == false
      assert error.compensation_error == "Refund failed"
      assert error.message == "Compensation failed for: Payment failed"
    end
  end

  describe "legacy new/4 compatibility" do
    test "maps old error types to new ones" do
      error = Error.new(:validation_error, "Test message", %{field: :test})
      assert %Error.InvalidInputError{} = error
      assert error.message == "Test message"
      assert error.details == %{field: :test}

      error = Error.new(:execution_error, "Test message")
      assert %Error.ExecutionFailureError{} = error
      assert error.message == "Test message"

      error = Error.new(:timeout, "Test message", %{timeout: 5000})
      assert %Error.TimeoutError{} = error
      assert error.message == "Test message"
      assert error.timeout == 5000
    end

    test "handles unknown error types" do
      error = Error.new(:unknown_type, "Test message", %{test: true})
      assert %Error.InternalError{} = error
      assert error.message == "Unknown error type: unknown_type - Test message"
      assert error.details == %{test: true}
    end
  end

  describe "to_map/1" do
    test "converts error struct to legacy map format" do
      error = Error.validation_error("Test message", %{field: "test"})
      map = Error.to_map(error)

      assert map.type == :validation_error
      assert map.message == "Test message"
      assert map.details == %{field: "test"}
      assert is_list(map.stacktrace)
    end

    test "handles different error types" do
      error = Error.execution_error("Test message")
      map = Error.to_map(error)
      assert map.type == :execution_error

      error = Error.timeout_error("Test message")
      map = Error.to_map(error)
      assert map.type == :timeout

      error = Error.config_error("Test message")
      map = Error.to_map(error)
      assert map.type == :config_error
    end

    test "handles non-error values" do
      map = Error.to_map("string error")
      assert map.type == :internal_server_error
      assert map.message == "\"string error\""
      assert is_list(map.stacktrace)
    end
  end

  describe "capture_stacktrace/0" do
    test "returns a list" do
      assert is_list(Error.capture_stacktrace())
    end

    test "captures current stacktrace" do
      stacktrace = Error.capture_stacktrace()
      assert length(stacktrace) > 0
      assert {JidoTest.ErrorTest, _, _, _} = hd(stacktrace)
    end
  end

  describe "NimbleOptions formatting" do
    test "formats config errors" do
      error = %NimbleOptions.ValidationError{
        keys_path: [:name],
        message: "is required"
      }

      formatted = Error.format_nimble_config_error(error, "Action", MyModule)

      assert formatted ==
               "Invalid configuration given to use Jido.Action (Elixir.MyModule) for key [:name]: is required"
    end

    test "formats validation errors" do
      error = %NimbleOptions.ValidationError{
        keys_path: [:input],
        message: "is required"
      }

      formatted = Error.format_nimble_validation_error(error, "Action", MyModule)

      assert formatted ==
               "Invalid parameters for Action (Elixir.MyModule) at [:input]: is required"
    end
  end

  describe "error aggregation and classification" do
    test "errors can be raised and handled as exceptions" do
      assert_raise Error.InvalidInputError, "Test message", fn ->
        raise Error.validation_error("Test message")
      end
    end

    test "errors can be pattern matched by type" do
      error = Error.validation_error("Test message")

      result =
        case error do
          %Error.InvalidInputError{} -> :validation
          %Error.ExecutionFailureError{} -> :execution
          %Error.TimeoutError{} -> :timeout
          _ -> :other
        end

      assert result == :validation
    end
  end
end
