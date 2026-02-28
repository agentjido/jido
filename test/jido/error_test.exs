defmodule JidoTest.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Error

  describe "validation_error/2" do
    test "creates a validation error with message" do
      error = Error.validation_error("Invalid input")

      assert %Error.ValidationError{} = error
      assert error.message == "Invalid input"
    end

    test "creates a validation error with field (infers kind: :input)" do
      error = Error.validation_error("Invalid field", field: :email)

      assert error.message == "Invalid field"
      assert error.kind == :input
      assert error.subject == :email
    end

    test "creates a validation error with explicit kind and subject" do
      error = Error.validation_error("Invalid", kind: :config, subject: :timeout)

      assert error.kind == :config
      assert error.subject == :timeout
    end

    test "creates a validation error for action (convenience)" do
      error = Error.validation_error("Action not found", action: SomeAction)

      assert error.message == "Action not found"
      assert error.kind == :action
      assert error.subject == SomeAction
    end

    test "creates a validation error for sensor (convenience)" do
      error = Error.validation_error("Sensor failed", sensor: SomeSensor)

      assert error.message == "Sensor failed"
      assert error.kind == :sensor
      assert error.subject == SomeSensor
    end
  end

  describe "execution_error/2" do
    test "creates an execution error" do
      error = Error.execution_error("Execution failed")

      assert %Error.ExecutionError{} = error
      assert error.message == "Execution failed"
      assert error.phase == :execution
    end

    test "creates an execution error with planning phase" do
      error = Error.execution_error("Planning failed", phase: :planning)

      assert error.message == "Planning failed"
      assert error.phase == :planning
    end

    test "creates an execution error with details" do
      error = Error.execution_error("Failed", details: %{step: :process})

      assert error.details[:step] == :process
    end
  end

  describe "routing_error/2" do
    test "creates a routing error" do
      error = Error.routing_error("Route not found", target: :agent_1)

      assert %Error.RoutingError{} = error
      assert error.message == "Route not found"
      assert error.target == :agent_1
    end
  end

  describe "timeout_error/2" do
    test "creates a timeout error" do
      error = Error.timeout_error("Operation timed out", timeout: 5000)

      assert %Error.TimeoutError{} = error
      assert error.message == "Operation timed out"
      assert error.timeout == 5000
    end
  end

  describe "compensation_error/2" do
    test "creates a compensation error for successful compensation" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error("Compensated",
          original_error: original,
          compensated: true,
          result: %{refund: true}
        )

      assert %Error.CompensationError{} = error
      assert error.compensated == true
      assert error.original_error == original
      assert error.result == %{refund: true}
    end

    test "creates a compensation error for failed compensation" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error("Compensation failed",
          original_error: original,
          compensated: false
        )

      assert error.compensated == false
      assert error.original_error == original
    end
  end

  describe "internal_error/2" do
    test "creates an internal error" do
      error = Error.internal_error("Unexpected error")

      assert %Error.InternalError{} = error
      assert error.message == "Unexpected error"
    end

    test "creates an internal error with details" do
      error = Error.internal_error("Failed", details: %{reason: :unknown})

      assert error.details[:reason] == :unknown
    end
  end

  describe "format_nimble_config_error/3" do
    test "formats error without keys path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "invalid option"}
      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration"
      assert result =~ "invalid option"
    end

    test "formats error with keys path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:schema, :name],
        message: "required"
      }

      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration"
      assert result =~ "[:schema, :name]"
    end

    test "handles binary and other error types" do
      assert Error.format_nimble_config_error("plain string error", "Agent", TestAgent) ==
               "plain string error"

      assert Error.format_nimble_config_error({:error, :unknown}, "Agent", TestAgent) =~
               ":error"
    end
  end

  describe "format_nimble_validation_error/3" do
    test "formats validation error without keys path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "invalid value"}
      result = Error.format_nimble_validation_error(nimble_error, "Action", TestAction)

      assert result =~ "Invalid parameters"
      assert result =~ "invalid value"
    end

    test "formats validation error with keys path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:params, :id],
        message: "must be integer"
      }

      result = Error.format_nimble_validation_error(nimble_error, "Action", TestAction)

      assert result =~ "Invalid parameters"
      assert result =~ "[:params, :id]"
    end

    test "handles binary and other validation error types" do
      assert Error.format_nimble_validation_error("plain string", "Action", TestAction) ==
               "plain string"

      assert Error.format_nimble_validation_error({:error, :bad}, "Action", TestAction) =~
               ":error"
    end
  end

  describe "to_map/1" do
    @to_map_cases [
      # {description, error_expr, expected_type}
      {"validation error with field", Error.validation_error("Invalid", field: :email),
       :validation_error},
      {"validation error with kind: :action",
       Error.validation_error("Bad action", action: SomeAction), :invalid_action},
      {"validation error with kind: :sensor",
       Error.validation_error("Bad sensor", sensor: SomeSensor), :invalid_sensor},
      {"validation error with kind: :config", Error.validation_error("Bad config", kind: :config),
       :config_error},
      {"execution error", Error.execution_error("Failed"), :execution_error},
      {"execution error with phase: :planning",
       Error.execution_error("Planning failed", phase: :planning), :planning_error},
      {"routing error", Error.routing_error("Route not found", target: :agent), :routing_error},
      {"timeout error", Error.timeout_error("Timed out", timeout: 5000), :timeout},
      {"internal error", Error.internal_error("Internal"), :internal}
    ]

    for {desc, error, expected_type} <- @to_map_cases do
      @desc desc
      @error error
      @expected_type expected_type

      test "converts #{@desc} to map with type #{@expected_type}" do
        result = Error.to_map(@error)
        assert result.type == @expected_type
      end
    end

    test "converts validation error to map with message and stacktrace" do
      error = Error.validation_error("Invalid", field: :email)
      result = Error.to_map(error)

      assert result.type == :validation_error
      assert result.message == "Invalid"
      assert is_list(result.stacktrace)
    end

    test "converts compensation error to map" do
      original = Error.execution_error("Original")
      error = Error.compensation_error("Compensated", original_error: original, compensated: true)
      result = Error.to_map(error)

      assert result.type == :compensation_error
    end

    test "handles unknown struct" do
      result = Error.to_map(%{unknown: "struct"})

      assert result.type == :internal
    end
  end

  describe "Splode interop" do
    test "to_error/1 keeps Jido validation errors typed and classified" do
      error = Error.validation_error("Invalid", field: :email)
      converted = Error.to_error(error)

      assert %Error.ValidationError{} = converted
      assert converted.class == :invalid
      assert converted.message == "Invalid"
    end

    test "to_class/1 wraps typed errors in the corresponding class" do
      error = Error.validation_error("Invalid", field: :email)
      class_error = Error.to_class(error)

      assert %Error.Invalid{} = class_error
      assert class_error.class == :invalid
      assert [%Error.ValidationError{}] = class_error.errors
    end

    test "to_error/1 preserves unknown error message for plain values" do
      unknown = Error.to_error("plain failure")

      assert %Error.Internal.UnknownError{} = unknown
      assert unknown.class == :internal
      assert unknown.message == "plain failure"
    end

    test "to_class/1 handles unknown values without raising" do
      class_error = Error.to_class("plain failure")

      assert %Error.Internal{} = class_error
      assert class_error.class == :internal
      assert [%Error.Internal.UnknownError{} = wrapped] = class_error.errors
      assert wrapped.message == "plain failure"
    end
  end

  describe "extract_message/1" do
    test "extracts message from various structures" do
      assert Error.extract_message(%{message: %{message: "Nested"}}) == "Nested"
      assert Error.extract_message(%{message: "Direct"}) == "Direct"
      assert Error.extract_message(%{message: nil}) == ""

      inner = struct(Error.InternalError, message: "Struct message", details: %{})
      assert Error.extract_message(%{message: inner}) == "Struct message"

      assert Error.extract_message("plain string") =~ "plain string"
    end
  end

  describe "capture_stacktrace/0" do
    test "returns current stacktrace" do
      stacktrace = Error.capture_stacktrace()

      assert is_list(stacktrace)
      assert stacktrace != []
    end
  end
end
