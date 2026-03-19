defmodule JidoTest.ErrorCoverageTest do
  use JidoTest.Case, async: true

  alias Jido.Error
  alias Jido.Error.Internal.UnknownError

  describe "error constructors with map options" do
    test "validation_error accepts map opts" do
      error = Error.validation_error("Invalid", %{kind: :config, subject: :timeout})

      assert %Error.ValidationError{} = error
      assert error.kind == :config
      assert error.subject == :timeout
    end

    test "validation_error with map opts and action key" do
      error = Error.validation_error("Bad action", %{action: SomeAction})

      assert error.kind == :action
      assert error.subject == SomeAction
    end

    test "validation_error with map opts and sensor key" do
      error = Error.validation_error("Bad sensor", %{sensor: SomeSensor})

      assert error.kind == :sensor
      assert error.subject == SomeSensor
    end

    test "execution_error accepts map opts" do
      error = Error.execution_error("Failed", %{phase: :planning, details: %{step: 1}})

      assert %Error.ExecutionError{} = error
      assert error.phase == :planning
      assert error.details == %{step: 1}
    end

    test "execution_error treats bare map opts as details" do
      error = Error.execution_error("Failed", %{phase: :planning, reason: :timeout})

      assert %Error.ExecutionError{} = error
      assert error.phase == :planning
      assert error.details == %{reason: :timeout}
    end

    test "routing_error accepts map opts" do
      error = Error.routing_error("No route", %{target: :agent_1, details: %{reason: :unknown}})

      assert %Error.RoutingError{} = error
      assert error.target == :agent_1
      assert error.details == %{reason: :unknown}
    end

    test "timeout_error accepts map opts" do
      error = Error.timeout_error("Timed out", %{timeout: 3000, details: %{operation: :fetch}})

      assert %Error.TimeoutError{} = error
      assert error.timeout == 3000
      assert error.details == %{operation: :fetch}
    end

    test "compensation_error accepts map opts" do
      original = Error.execution_error("Original failure")

      error =
        Error.compensation_error("Compensated", %{
          original_error: original,
          compensated: true,
          result: :ok,
          details: %{action: :rollback}
        })

      assert %Error.CompensationError{} = error
      assert error.original_error == original
      assert error.compensated == true
      assert error.result == :ok
      assert error.details == %{action: :rollback}
    end

    test "internal_error accepts map opts" do
      error = Error.internal_error("Unexpected", %{details: %{code: 500}})

      assert %Error.InternalError{} = error
      assert error.details == %{code: 500}
    end
  end

  describe "validation_error convenience keys" do
    test "action key sets kind to :action and subject to the action module" do
      error = Error.validation_error("Invalid action", action: MyModule.SomeAction)

      assert error.kind == :action
      assert error.subject == MyModule.SomeAction
    end

    test "sensor key sets kind to :sensor and subject to the sensor module" do
      error = Error.validation_error("Invalid sensor", sensor: MyModule.SomeSensor)

      assert error.kind == :sensor
      assert error.subject == MyModule.SomeSensor
    end

    test "action key takes precedence over sensor key" do
      error =
        Error.validation_error("Test", action: ActionModule, sensor: SensorModule)

      assert error.kind == :action
      assert error.subject == ActionModule
    end

    test "field key infers kind :input" do
      error = Error.validation_error("Invalid field", field: :username)

      assert error.kind == :input
      assert error.subject == :username
    end
  end

  describe "extract_message edge cases" do
    test "handles nil message" do
      assert Error.extract_message(%{message: nil}) == ""
    end

    test "handles struct message with message field" do
      inner_struct = %Error.InternalError{message: "Inner error", details: %{}}
      assert Error.extract_message(%{message: inner_struct}) == "Inner error"
    end

    test "handles struct message without message field" do
      inner_struct = %{__struct__: SomeStruct, data: "value"}
      result = Error.extract_message(%{message: inner_struct})
      assert is_binary(result)
      assert result =~ "SomeStruct"
    end

    test "handles nested message with inner message" do
      assert Error.extract_message(%{message: %{message: "Deeply nested"}}) == "Deeply nested"
    end

    test "handles non-struct non-map error" do
      assert Error.extract_message(:some_atom) =~ ":some_atom"
      assert Error.extract_message(123) =~ "123"
      assert Error.extract_message({:error, :reason}) =~ ":error"
    end
  end

  describe "to_map with non-struct errors" do
    test "handles plain map without message key" do
      result = Error.to_map(%{some: "data"})

      assert result.type == :internal
      assert result.message =~ "some"
      assert result.details == %{}
      assert is_list(result.stacktrace)
    end

    test "handles string error" do
      result = Error.to_map("plain string error")

      assert result.type == :internal
      assert result.message =~ "plain string error"
      assert result.details == %{}
    end

    test "handles tuple error" do
      result = Error.to_map({:error, :unknown_reason})

      assert result.type == :internal
      assert result.message =~ ":error"
      assert result.message =~ ":unknown_reason"
    end

    test "handles atom error" do
      result = Error.to_map(:some_error)

      assert result.type == :internal
      assert result.message =~ ":some_error"
    end

    test "handles integer" do
      result = Error.to_map(500)

      assert result.type == :internal
      assert result.message == "500"
    end

    test "handles nil" do
      result = Error.to_map(nil)

      assert result.type == :internal
      assert result.message == "nil"
    end

    test "handles map with message key but no details" do
      result = Error.to_map(%{message: "Error message"})

      assert result.type == :internal
      assert result.message == "Error message"
      assert result.details == %{}
    end
  end

  describe "unified_type for Jido error structs" do
    test "ValidationError with kind :action returns :invalid_action" do
      error = Error.validation_error("Bad", kind: :action, subject: SomeAction)
      result = Error.to_map(error)
      assert result.type == :invalid_action
    end

    test "ValidationError with kind :sensor returns :invalid_sensor" do
      error = Error.validation_error("Bad", kind: :sensor, subject: SomeSensor)
      result = Error.to_map(error)
      assert result.type == :invalid_sensor
    end

    test "ValidationError with kind :config returns :config_error" do
      error = Error.validation_error("Bad", kind: :config)
      result = Error.to_map(error)
      assert result.type == :config_error
    end

    test "ValidationError without kind returns :validation_error" do
      error = Error.validation_error("Bad")
      result = Error.to_map(error)
      assert result.type == :validation_error
    end

    test "ExecutionError with phase :planning returns :planning_error" do
      error = Error.execution_error("Failed", phase: :planning)
      result = Error.to_map(error)
      assert result.type == :planning_error
    end

    test "ExecutionError without phase returns :execution_error" do
      error = Error.execution_error("Failed")
      result = Error.to_map(error)
      assert result.type == :execution_error
    end

    test "RoutingError returns :routing_error" do
      error = Error.routing_error("No route")
      result = Error.to_map(error)
      assert result.type == :routing_error
    end

    test "TimeoutError returns :timeout" do
      error = Error.timeout_error("Timed out")
      result = Error.to_map(error)
      assert result.type == :timeout
    end

    test "CompensationError returns :compensation_error" do
      error = Error.compensation_error("Compensated")
      result = Error.to_map(error)
      assert result.type == :compensation_error
    end

    test "InternalError returns :internal" do
      error = Error.internal_error("Internal")
      result = Error.to_map(error)
      assert result.type == :internal
    end

    test "UnknownError returns :internal" do
      error = UnknownError.exception(message: "Unknown")
      result = Error.to_map(error)
      assert result.type == :internal
    end
  end

  describe "unified_type for cross-package errors (Jido.Action.Error.*)" do
    test "InvalidInputError returns :validation_error" do
      error = %Jido.Action.Error.InvalidInputError{message: "Bad input", details: %{}}
      result = Error.to_map(error)
      assert result.type == :validation_error
    end

    test "ExecutionFailureError returns :execution_error" do
      error = %Jido.Action.Error.ExecutionFailureError{message: "Failed", details: %{}}
      result = Error.to_map(error)
      assert result.type == :execution_error
    end

    test "TimeoutError returns :timeout" do
      error = %Jido.Action.Error.TimeoutError{message: "Timed out", details: %{}}
      result = Error.to_map(error)
      assert result.type == :timeout
    end

    test "ConfigurationError returns :config_error" do
      error = %Jido.Action.Error.ConfigurationError{message: "Bad config", details: %{}}
      result = Error.to_map(error)
      assert result.type == :config_error
    end

    test "InternalError returns :internal" do
      error = %Jido.Action.Error.InternalError{message: "Internal", details: %{}}
      result = Error.to_map(error)
      assert result.type == :internal
    end
  end

  describe "unified_type for cross-package errors (Jido.Signal.Error.*)" do
    test "InvalidInputError returns :validation_error" do
      error = %Jido.Signal.Error.InvalidInputError{message: "Bad input", details: %{}}
      result = Error.to_map(error)
      assert result.type == :validation_error
    end

    test "ExecutionFailureError returns :execution_error" do
      error = %Jido.Signal.Error.ExecutionFailureError{message: "Failed", details: %{}}
      result = Error.to_map(error)
      assert result.type == :execution_error
    end

    test "RoutingError returns :routing_error" do
      error = %Jido.Signal.Error.RoutingError{message: "No route", details: %{}}
      result = Error.to_map(error)
      assert result.type == :routing_error
    end

    test "TimeoutError returns :timeout" do
      error = %Jido.Signal.Error.TimeoutError{message: "Timed out", details: %{}}
      result = Error.to_map(error)
      assert result.type == :timeout
    end

    test "DispatchError returns :routing_error" do
      error = %Jido.Signal.Error.DispatchError{message: "Dispatch failed", details: %{}}
      result = Error.to_map(error)
      assert result.type == :routing_error
    end

    test "InternalError returns :internal" do
      error = %Jido.Signal.Error.InternalError{message: "Internal", details: %{}}
      result = Error.to_map(error)
      assert result.type == :internal
    end
  end

  describe "format_nimble_validation_error edge cases" do
    test "formats NimbleOptions.ValidationError with empty keys_path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "required option"}
      result = Error.format_nimble_validation_error(nimble_error, "Action", TestAction)

      assert result =~ "Invalid parameters for Action"
      assert result =~ "TestAction"
      assert result =~ "required option"
    end

    test "formats NimbleOptions.ValidationError with nested keys_path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:nested, :deep, :key],
        message: "must be positive"
      }

      result = Error.format_nimble_validation_error(nimble_error, "Sensor", TestSensor)

      assert result =~ "Invalid parameters for Sensor"
      assert result =~ "TestSensor"
      assert result =~ "[:nested, :deep, :key]"
      assert result =~ "must be positive"
    end

    test "passes through binary errors unchanged" do
      result = Error.format_nimble_validation_error("raw error string", "Action", TestAction)
      assert result == "raw error string"
    end

    test "inspects non-binary non-NimbleOptions errors" do
      result = Error.format_nimble_validation_error({:error, :bad_value}, "Action", TestAction)
      assert result =~ ":error"
      assert result =~ ":bad_value"
    end

    test "handles list error" do
      result = Error.format_nimble_validation_error([:error1, :error2], "Action", TestAction)
      assert result =~ ":error1"
      assert result =~ ":error2"
    end
  end

  describe "format_nimble_config_error edge cases" do
    test "formats NimbleOptions.ValidationError with empty keys_path" do
      nimble_error = %NimbleOptions.ValidationError{keys_path: [], message: "unknown option"}
      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration for Agent"
      assert result =~ "TestAgent"
      assert result =~ "unknown option"
    end

    test "formats NimbleOptions.ValidationError with keys_path" do
      nimble_error = %NimbleOptions.ValidationError{
        keys_path: [:config, :timeout],
        message: "must be integer"
      }

      result = Error.format_nimble_config_error(nimble_error, "Agent", TestAgent)

      assert result =~ "Invalid configuration for Agent"
      assert result =~ "TestAgent"
      assert result =~ "[:config, :timeout]"
      assert result =~ "must be integer"
    end

    test "passes through binary errors unchanged" do
      result = Error.format_nimble_config_error("config error string", "Agent", TestAgent)
      assert result == "config error string"
    end

    test "inspects non-binary non-NimbleOptions errors" do
      result = Error.format_nimble_config_error(%{error: :invalid}, "Agent", TestAgent)
      assert result =~ ":invalid"
    end
  end
end
