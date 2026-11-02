defmodule Jido.Signal.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.Error

  defmodule OtherError do
    defexception [:message, :code]
  end

  describe "constructors and types" do
    test "creates each concrete package error" do
      cases = [
        {Error.validation_error("invalid", field: :type, value: nil), :invalid_input_error},
        {Error.execution_error("failed", reason: :closed), :execution_failure_error},
        {Error.routing_error("no route", target: :worker), :routing_error},
        {Error.timeout_error("late", timeout: 100), :timeout_error},
        {Error.dispatch_error("not sent", reason: :closed), :dispatch_error},
        {Error.internal_error("broken", reason: :unknown), :internal_error}
      ]

      for {error, type} <- cases do
        assert is_exception(error)
        assert Error.type(error) == type
      end

      assert Error.validation_error("invalid").details == %{}

      assert Error.execution_error("failed", [:not, :a, :keyword]).details == %{
               value: [:not, :a, :keyword]
             }

      assert Error.internal_error("broken", nil).details == %{}
      assert Error.routing_error("no route", :worker).details == %{value: :worker}
    end

    test "keeps stable defaults for concrete errors" do
      cases = [
        {Error.InvalidInputError, "Invalid input"},
        {Error.ExecutionFailureError, "Signal processing failed"},
        {Error.RoutingError, "Signal routing failed"},
        {Error.TimeoutError, "Signal processing timed out"},
        {Error.DispatchError, "Signal dispatch failed"},
        {Error.InternalError, "Internal error"},
        {Error.Internal.UnknownError, "Unknown error"}
      ]

      for {module, message} <- cases do
        error = module.exception([])
        assert Exception.message(error) == message
        assert error.details == %{}
      end
    end

    test "reports Splode class types" do
      assert Error.type(struct(Error.Invalid)) == :invalid
      assert Error.type(struct(Error.Execution)) == :execution
      assert Error.type(struct(Error.Routing)) == :routing
      assert Error.type(struct(Error.Timeout)) == :timeout
      assert Error.type(struct(Error.Internal)) == :internal
      assert Error.type(Error.Internal.UnknownError.exception([])) == :unknown_error
    end
  end

  describe "normalize/1" do
    test "keeps local errors and unwraps error tuples" do
      error = Error.dispatch_error("failed")
      assert Error.normalize(error) == error
      assert Error.normalize({:error, error}) == error
    end

    test "maps common foreign failures to package errors" do
      assert %Error.InvalidInputError{message: "bad argument"} =
               Error.normalize(ArgumentError.exception("bad argument"))

      assert %Error.ExecutionFailureError{message: "crashed"} =
               Error.normalize(RuntimeError.exception("crashed"))

      assert %Error.InternalError{message: "other"} =
               Error.normalize(OtherError.exception(message: "other", code: 10))

      assert %Error.InternalError{message: "text failure"} = Error.normalize("text failure")

      assert %Error.InternalError{details: %{reason: :closed}} = Error.normalize(:closed)

      assert %Error.InternalError{details: %{reason: [one: 1]}} = Error.normalize(one: 1)
    end

    test "normalizes values before type and public map output" do
      assert Error.type(:closed) == :internal_error

      assert %{
               type: :internal_error,
               message: "Signal processing failed",
               details: %{"reason" => "closed"},
               retryable?: true
             } = Error.to_map(:closed)
    end
  end

  describe "to_map/1" do
    test "serializes a stable public error payload" do
      error =
        Error.dispatch_error("upstream request failed", %{
          reason: {:status_error, 503, "unavailable"},
          token: "secret-token",
          context: {:retry, %{attempt: 2}}
        })

      assert %{
               type: :dispatch_error,
               message: "upstream request failed",
               details: details,
               retryable?: true
             } = Error.to_map(error)

      assert details["token"] == "[REDACTED]"

      assert details["reason"] == %{
               "__type__" => "tuple",
               "items" => ["status_error", 503, "unavailable"]
             }

      assert details["context"] == %{
               "__type__" => "tuple",
               "items" => ["retry", %{"attempt" => 2}]
             }
    end

    test "redacts sensitive pairs in public error details" do
      error =
        Error.internal_error("failed", %{
          mixed: [{:password, "mixed-secret"}, :tail],
          improper: [{:token, "improper-secret"} | :tail]
        })

      public = Error.to_map(error)

      assert inspect(public) =~ "[REDACTED]"
      refute inspect(public) =~ "mixed-secret"
      refute inspect(public) =~ "improper-secret"
    end

    test "preserves grouped package error classes" do
      grouped = struct(Error.Execution, errors: [Error.timeout_error("late")])

      assert %{
               type: :execution,
               message: "Signal processing failed",
               retryable?: true
             } = Error.to_map(grouped)

      public = Error.to_map(grouped)
      refute public.message =~ "splode"
      refute public.message =~ "error_test.exs"

      wrapped = Error.dispatch_error("dispatch failed", reason: grouped)
      assert Error.retryable?(wrapped)
    end
  end

  describe "retryable?/1" do
    test "does not traverse improper grouped error lists" do
      for head <- [Error.validation_error("bad"), Error.timeout_error("late")] do
        errors = [head | :tail]
        foreign = %{errors: errors}
        grouped = struct(Error.Execution, errors: errors)
        wrapped = Error.dispatch_error("outer", reason: foreign)

        for error <- [foreign, grouped, wrapped] do
          refute Error.retryable?(error)
          refute Error.to_map(error).retryable?
        end
      end
    end

    test "derives timeout retryability centrally" do
      assert Error.retryable?(Error.timeout_error("timed out", %{timeout: 1000}))
      refute Error.retryable?(Error.validation_error("bad input", %{field: :type}))
    end

    test "classifies HTTP status and transport failures" do
      assert Error.retryable?(dispatch_error({:http_status, 503}))
      assert Error.retryable?(dispatch_error({:http_status, 429}))
      assert Error.retryable?(dispatch_error({:transport, {:failed_connect, :econnrefused}}))

      refute Error.retryable?(dispatch_error({:http_status, 400}))
      refute Error.retryable?(dispatch_error({:transport, :certificate_expired}))
    end

    test "ignores a non-Boolean retry override" do
      refute Error.retryable?(Error.dispatch_error("failed", %{retryable?: :yes}))
    end

    test "supports explicit and nested retry reasons" do
      assert Error.retryable?(Error.execution_error("failed", retryable?: true))
      assert Error.retryable?(Error.internal_error("failed", error: :queue_full))

      unknown = Error.Internal.UnknownError.exception(details: %{reason: :retry_failed})
      assert Error.retryable?(unknown)

      nested =
        Error.dispatch_error("outer", reason: Error.dispatch_error("inner", reason: :closed))

      assert Error.retryable?(nested)

      execution = Error.execution_error("outer", reason: Error.timeout_error("late"))
      assert Error.retryable?(execution)

      internal = Error.internal_error("outer", reason: unknown)
      assert Error.retryable?(internal)
    end

    test "classifies all stable retry reason forms" do
      for reason <- [
            :timeout,
            :econnrefused,
            :closed,
            :closed_remotely,
            :retry_failed,
            :queue_full,
            :subscription_not_available,
            :circuit_open,
            {:http_status, 408},
            {:http_status, 425},
            {:status_error, 429, "busy"},
            {:status_error, 500, "failed"},
            {:failed_connect, :econnrefused},
            {:transport, :timeout}
          ] do
        assert Error.retryable?(dispatch_error(reason)), "expected retry for #{inspect(reason)}"
      end

      refute Error.retryable?(dispatch_error({:http_status, 499}))
      refute Error.retryable?(dispatch_error({:status_error, 499, "failed"}))
      refute Error.retryable?(dispatch_error({:exception, RuntimeError.exception("failed")}))
    end

    test "checks grouped Splode errors" do
      grouped = struct(Error.Execution, errors: [Error.timeout_error("late")])
      assert Error.retryable?(grouped)

      grouped = struct(Error.Invalid, errors: [Error.validation_error("bad")])
      refute Error.retryable?(grouped)
    end
  end

  defp dispatch_error(reason) do
    Error.dispatch_error("dispatch failed", %{reason: reason})
  end
end
