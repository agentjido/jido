defmodule JidoTest.Error.NormalizationTest do
  use Covenant.Case, component: "jido.error", async: true

  alias Jido.Error
  alias Jido.Error.Internal.UnknownError

  @tag obligation: "jido.error.I1"
  test "constructors accept map options and keep their owned fields" do
    validation = Error.validation_error("Invalid", %{kind: :config, subject: :timeout})
    action = Error.validation_error("Bad action", %{action: SomeAction})
    execution = Error.execution_error("Failed", %{phase: :planning, reason: :timeout})
    routing = Error.routing_error("No route", %{target: :agent, details: %{reason: :unknown}})
    timeout = Error.timeout_error("Timed out", %{timeout: 3_000, details: %{operation: :fetch}})
    original = Error.execution_error("Original")

    compensation =
      Error.compensation_error("Compensated", %{
        original_error: original,
        compensated: true,
        result: :ok,
        details: %{action: :rollback}
      })

    internal = Error.internal_error("Unexpected", %{details: %{reason: :unknown}})

    assert {validation.kind, validation.subject} == {:config, :timeout}
    assert {action.kind, action.subject} == {:action, SomeAction}
    assert {execution.phase, execution.details} == {:planning, %{reason: :timeout}}
    assert {routing.target, routing.details} == {:agent, %{reason: :unknown}}
    assert {timeout.timeout, timeout.details} == {3_000, %{operation: :fetch}}

    assert {compensation.original_error, compensation.compensated, compensation.result,
            compensation.details} == {original, true, :ok, %{action: :rollback}}

    assert internal.details == %{reason: :unknown}
  end

  @tag obligation: "jido.error.I1"
  test "all error modules normalize malformed details to an empty map" do
    errors = [
      Error.validation_error("Invalid", details: :invalid),
      Error.execution_error("Failed", details: :invalid),
      Error.routing_error("No route", details: :invalid),
      Error.timeout_error("Timed out", details: :invalid),
      Error.compensation_error("Failed", details: :invalid),
      Error.internal_error("Internal", details: :invalid),
      UnknownError.exception(message: "Unknown", details: :invalid)
    ]

    assert Enum.all?(errors, &(&1.details == %{}))
  end

  @tag obligation: ["jido.error.I3", "jido.error.I6"]
  test "unknown values use the exact defensive internal projection" do
    for {error, message} <- [
          {%{some: "data"}, "some"},
          {"plain string error", "plain string error"},
          {{:error, :unknown_reason}, ":unknown_reason"},
          {:some_error, ":some_error"},
          {500, "500"},
          {nil, "nil"},
          {%{message: "Error message"}, "Error message"}
        ] do
      projection = Error.to_map(error)

      assert Map.keys(projection) |> Enum.sort() == [:details, :message, :retryable?, :type]
      assert projection.type == :internal
      assert projection.message =~ message
      assert projection.details == %{}
      assert projection.retryable?
    end
  end

  @tag obligation: "jido.error.I3"
  test "projects adjacent Action errors without changing their ownership" do
    errors = [
      {%Jido.Action.Error.InvalidInputError{message: "Bad input", details: %{}},
       :validation_error},
      {%Jido.Action.Error.ExecutionFailureError{message: "Failed", details: %{}},
       :execution_error},
      {%Jido.Action.Error.TimeoutError{message: "Timed out", details: %{}}, :timeout},
      {%Jido.Action.Error.ConfigurationError{message: "Bad config", details: %{}}, :config_error},
      {%Jido.Action.Error.InternalError{message: "Internal", details: %{}}, :internal}
    ]

    for {error, type} <- errors do
      assert Error.to_map(error).type == type
      assert error.__struct__ != Error.ValidationError
      assert error.__struct__ != Error.ExecutionError
    end
  end

  @tag obligation: "jido.error.I3"
  test "projects adjacent Signal errors without changing their ownership" do
    errors = [
      {%Jido.Signal.Error.InvalidInputError{message: "Bad input", details: %{}},
       :validation_error},
      {%Jido.Signal.Error.ExecutionFailureError{message: "Failed", details: %{}},
       :execution_error},
      {%Jido.Signal.Error.RoutingError{message: "No route", details: %{}}, :routing_error},
      {%Jido.Signal.Error.TimeoutError{message: "Timed out", details: %{}}, :timeout},
      {%Jido.Signal.Error.DispatchError{message: "Dispatch failed", details: %{}},
       :routing_error},
      {%Jido.Signal.Error.InternalError{message: "Internal", details: %{}}, :internal}
    ]

    for {error, type} <- errors do
      assert Error.to_map(error).type == type
      assert String.starts_with?(inspect(error.__struct__), "Jido.Signal.Error.")
    end
  end

  @tag obligation: "jido.error.I3"
  test "projects Agent authoring errors by their shared meaning" do
    unmatched = %Jido.Agent.Error{code: :unmatched_input, message: "No route"}
    invalid = %Jido.Agent.Error{code: :invalid_state, message: "Invalid state"}

    assert Error.to_map(unmatched).type == :routing_error
    assert Error.to_map(invalid).type == :validation_error
  end
end
