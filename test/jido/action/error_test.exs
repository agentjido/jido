defmodule JidoActionTest.Action.ErrorTest do
  use Covenant.Case, component: "jido_action.errors", async: true

  alias Jido.Action.Error
  alias Jido.Action.Error.Internal.UnknownError

  describe "error construction" do
    @describetag obligation: "jido_action.errors.I1"

    test "constructors create the concrete Action errors" do
      assert %Error.InvalidInputError{message: "invalid"} =
               Error.validation_error("invalid")

      assert %Error.ExecutionFailureError{message: "failed"} =
               Error.execution_error("failed")

      assert %Error.ConfigurationError{message: "bad config"} =
               Error.config_error("bad config")

      assert %Error.TimeoutError{message: "slow"} = Error.timeout_error("slow")
      assert %Error.InternalError{message: "broken"} = Error.internal_error("broken")
    end

    test "constructors accept plain maps and keyword details" do
      assert %Error.InvalidInputError{
               field: :count,
               value: -1,
               details: %{field: :count, value: -1}
             } = Error.validation_error("invalid", field: :count, value: -1)

      assert %Error.TimeoutError{timeout: 500, details: %{timeout: 500}} =
               Error.timeout_error("slow", %{timeout: 500})
    end

    test "constructors discard unsupported detail containers" do
      struct_details = Error.execution_error("failed", URI.parse("https://example.com"))
      assert struct_details.details == %{}

      scalar_details = Error.execution_error("failed", "not details")
      assert scalar_details.details == %{}
    end
  end

  describe "Splode compatibility" do
    @describetag obligation: "jido_action.errors.I1"

    test "concrete errors use their expected classes" do
      assert Error.validation_error("invalid").class == :invalid
      assert Error.execution_error("failed").class == :execution
      assert Error.timeout_error("slow").class == :execution
      assert Error.config_error("bad config").class == :config
      assert Error.internal_error("broken").class == :internal
    end

    test "invalid errors take precedence when Splode aggregates errors" do
      error =
        Error.to_class([
          Error.execution_error("failed"),
          Error.validation_error("invalid")
        ])

      assert %Error.Invalid{class: :invalid} = error
    end
  end

  describe "to_map/1" do
    @describetag obligation: "jido_action.errors.I3"

    test "normalizes the concrete Action errors" do
      cases = [
        {Error.validation_error("invalid", field: :count), :validation_error, false},
        {Error.execution_error("failed"), :execution_error, false},
        {Error.timeout_error("slow", timeout: 500), :timeout, false},
        {Error.config_error("bad config"), :configuration_error, false},
        {Error.internal_error("broken"), :internal_error, false},
        {UnknownError.exception(message: "unknown"), :internal_error, false}
      ]

      for {error, type, retryable?} <- cases do
        assert %{
                 type: ^type,
                 message: message,
                 details: details,
                 retryable?: ^retryable?
               } = Error.to_map(error)

        assert is_binary(message)
        assert is_map(details)
      end
    end

    test "preserves fields owned by concrete errors" do
      assert %{
               details: %{field: :count, value: -1},
               retryable?: false
             } = Error.to_map(Error.validation_error("invalid", field: :count, value: -1))

      assert %{details: %{timeout: 500}, retryable?: false} =
               Error.to_map(Error.timeout_error("slow", timeout: 500))

      assert %{retryable?: true} =
               Error.to_map(Error.timeout_error("slow", timeout: 500, retry: true))
    end

    test "unwraps standard error tuples" do
      error = Error.config_error("bad config")

      assert Error.to_map({:error, error}) == Error.to_map(error)
      assert Error.to_map({:error, error, %{effect: :ignored}}) == Error.to_map(error)
    end

    test "flattens every unsupported reason conservatively" do
      for reason <- [
            :badarg,
            "plain failure",
            42,
            {:remote, :failure},
            %{type: :timeout, message: "foreign"},
            %RuntimeError{message: "foreign"}
          ] do
        assert %{
                 type: :execution_error,
                 message: message,
                 details: %{},
                 retryable?: false
               } = Error.to_map(reason)

        assert is_binary(message)
      end
    end

    test "foreign maps cannot select an Action error type" do
      mapped = Error.to_map(%{type: :timeout, message: "foreign", retryable?: true})

      assert mapped.type == :execution_error
      assert mapped.retryable? == false
      assert mapped.details == %{}
    end

    test "preserves concrete error details without transport conversion" do
      owner = self()
      exception = RuntimeError.exception("broken")

      error =
        Error.execution_error("failed", %{
          tuple: {:error, :closed},
          owner: owner,
          exception: exception,
          payload: <<255>>
        })

      mapped = Error.to_map(error)

      assert mapped.details === error.details
      assert mapped.details.owner === owner
      assert mapped.details.exception === exception
      assert mapped.details.tuple === {:error, :closed}
      assert mapped.details.payload === <<255>>
    end

    test "uses the underlying message from a Splode unknown error" do
      cases = [
        {UnknownError.exception(message: "unknown"), "unknown"},
        {UnknownError.exception(error: "remote failure"), "remote failure"},
        {UnknownError.exception(error: :shutdown), "shutdown"},
        {UnknownError.exception(error: 42), "42"},
        {UnknownError.exception(error: {:remote, :failure}), "{:remote, :failure}"}
      ]

      for {error, message} <- cases do
        assert Error.to_map(error) == %{
                 type: :internal_error,
                 message: message,
                 details: %{},
                 retryable?: false
               }
      end
    end
  end

  describe "retryable?/1" do
    @describetag obligation: "jido_action.errors.I4"

    test "uses the concrete error type and a direct execution hint" do
      refute Error.retryable?(Error.validation_error("invalid"))
      refute Error.retryable?(Error.config_error("bad config"))
      refute Error.retryable?(Error.internal_error("broken"))
      refute Error.retryable?(UnknownError.exception(message: "unknown"))
      refute Error.retryable?(Error.timeout_error("slow"))
      assert Error.retryable?(Error.timeout_error("slow", retry: true))
      refute Error.retryable?(Error.execution_error("failed"))
      refute Error.retryable?(Error.execution_error("failed", retry: false))
      assert Error.retryable?(Error.execution_error("failed", retry: true))
    end

    test "unwraps error tuples" do
      cases = [
        {Error.timeout_error("slow"), false},
        {Error.timeout_error("slow", retry: true), true},
        {Error.execution_error("failed", retry: true), true},
        {Error.validation_error("invalid", retry: true), false},
        {UnknownError.exception(message: "unknown"), false}
      ]

      for {error, expected} <- cases do
        assert Error.retryable?(error) === expected
        assert Error.retryable?({:error, error}) === expected
        assert Error.retryable?({:error, error, [:ignored]}) === expected
      end
    end

    test "rejects non-Boolean direct retry hints" do
      for constructor <- [:execution_error, :timeout_error],
          hint <- [nil, 0, 1, "true", :retry, [], %{}] do
        error = apply(Error, constructor, ["failed", %{retry: hint}])

        assert Error.retryable?(error) === false
        assert Error.to_map(error).retryable? === false
      end
    end

    test "does not infer retry policy from unsupported values or nested details" do
      for reason <- [
            :timeout,
            %{type: :timeout, retryable?: true},
            %{details: %{reason: %{retry: true}}}
          ] do
        assert Error.retryable?(reason) === false
      end
    end
  end

  describe "JSON encoding" do
    @describetag obligation: "jido_action.errors.I3"

    test "does not provide transport encoding for error structs" do
      error = Error.execution_error("failed")

      assert_raise Protocol.UndefinedError, fn -> JSON.encode!(error) end
    end
  end
end
