defmodule JidoActionTest.Flow.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Action.Error, as: ActionError
  alias Jido.Flow.Error

  describe "constructors" do
    test "creates Flow-owned Splode errors" do
      definition = Error.validation_error("bad definition", path: [:components, 0])
      invalid_execution = Error.invalid_execution_error("not ready", runnable_id: 12)
      execution = Error.execution_error("failed", phase: :runic_execution)
      timeout = Error.timeout_error("too slow", timeout: 500, flow: "checkout")
      internal = Error.internal_error("compiler defect", phase: :flow_compilation)

      assert %Error.InvalidDefinitionError{class: :invalid} = definition
      assert %Error.InvalidExecutionError{class: :invalid} = invalid_execution
      assert %Error.ExecutionFailureError{class: :execution} = execution
      assert %Error.TimeoutError{class: :execution, timeout: 500, flow: "checkout"} = timeout
      assert %Error.InternalError{class: :internal} = internal

      assert Error.splode_error?(definition)
      assert Error.splode_error?(invalid_execution)
      assert Error.splode_error?(execution)
      assert Error.splode_error?(timeout)
      assert Error.splode_error?(internal)
    end

    test "normalizes constructor details" do
      assert %{details: %{path: [:output]}} =
               Error.validation_error("bad definition", path: [:output])

      assert %{details: %{}} = Error.execution_error("bad details", [:not_keyword])
      assert %{details: %{}} = Error.internal_error("bad details", :not_a_map)
      assert %Error.TimeoutError{details: %{}} = Error.timeout_error("too slow")
      assert %Error.InternalError{details: %{}} = Error.internal_error("broken")
      assert Error.retryable?(Error.timeout_error("temporary", retry: true))
    end
  end

  describe "Action error alignment" do
    test "merges Action failures without changing the leaf error" do
      action_error = ActionError.execution_error("action failed", retry: false)

      assert %Error.Execution{errors: [merged]} = Error.to_class([action_error, action_error])
      assert merged.__struct__ == action_error.__struct__
      assert merged.message == action_error.message
    end

    test "serializes Action errors through the Action error contract" do
      action_error = ActionError.validation_error("bad action input", field: :value)

      assert Error.to_map(action_error) == ActionError.to_map(action_error)
      refute Error.retryable?(action_error)
    end
  end

  describe "Flow execution failures" do
    test "uses an explicit retry value only when one is present" do
      assert Error.retryable?(Error.execution_error("temporary", retry: true))
      refute Error.retryable?(Error.execution_error("permanent"))
    end
  end

  describe "error maps" do
    test "keeps native Runic IDs in nested error details" do
      first = Runic.Identity.digest(:activation, :first)
      second = Runic.Identity.digest(:activation, :second)

      invalid =
        Error.invalid_execution_error("not ready", %{
          runnable_id: first,
          ready: [second],
          nested: %{ancestry: {first, second}},
          unrelated: MapSet.new([first]),
          improper: [first | :tail],
          malformed: %{first | digest: nil}
        })

      assert Error.to_map(invalid).details === invalid.details
    end

    test "maps each Flow leaf and Splode class" do
      definition = Error.validation_error("bad definition", field: :output)
      invalid_execution = Error.invalid_execution_error("not ready", runnable_id: 12)
      execution = Error.execution_error("failed", phase: :runic_execution)
      timeout = Error.timeout_error("too slow", timeout: 500, flow: "checkout")
      internal = Error.internal_error("compiler defect", phase: :flow_compilation)

      invalid_class =
        Error.to_class([
          definition,
          Error.validation_error("second bad definition", field: :components)
        ])

      execution_class =
        Error.to_class([
          execution,
          Error.execution_error("second failure", phase: :flow_output)
        ])

      internal_class =
        Error.to_class([
          internal,
          Error.internal_error("second defect", phase: :flow_materialization)
        ])

      unknown = Error.Internal.UnknownError.exception(error: :unknown_flow_failure)
      binary_unknown = Error.Internal.UnknownError.exception(error: "unknown flow failure")
      tuple_unknown = Error.Internal.UnknownError.exception(error: {:unknown, :flow_failure})
      message_unknown = Error.Internal.UnknownError.exception(message: "explicit failure")

      assert %Error.Invalid{} = invalid_class
      assert %Error.Execution{} = execution_class
      assert %Error.Internal{} = internal_class
      assert Exception.message(unknown) == "unknown_flow_failure"
      assert Exception.message(binary_unknown) == "unknown flow failure"
      assert Exception.message(tuple_unknown) == "{:unknown, :flow_failure}"
      assert Exception.message(message_unknown) == "explicit failure"

      errors = [
        definition,
        invalid_execution,
        execution,
        timeout,
        internal,
        invalid_class,
        execution_class,
        internal_class,
        unknown
      ]

      for error <- errors do
        assert %{type: type, message: message, details: details, retryable?: retryable?} =
                 Error.to_map(error)

        assert is_atom(type)
        assert is_binary(message)
        assert is_map(details)
        assert is_boolean(retryable?)
        refute Error.retryable?(error)
      end
    end

    test "does not provide transport encoding for Flow error structs" do
      assert_raise Protocol.UndefinedError, fn ->
        Error.validation_error("bad definition") |> JSON.encode!()
      end
    end

    test "accepts error tuples and delegates unsupported values" do
      error = Error.invalid_execution_error("not ready")
      assert Error.to_map({:error, error}) == Error.to_map(error)
      assert Error.to_map({:error, error, %{effect: :none}}) == Error.to_map(error)
      refute Error.retryable?({:error, error})
      refute Error.retryable?({:error, error, %{effect: :none}})

      assert Error.to_map(:foreign_failure) == ActionError.to_map(:foreign_failure)
    end
  end
end
