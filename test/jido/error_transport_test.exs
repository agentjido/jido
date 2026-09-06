defmodule JidoTest.ErrorTransportTest do
  use ExUnit.Case, async: true
  alias Jido.Error

  defmodule BadInspect do
    defstruct [:token]
  end

  defmodule ValidationAction do
    use Jido.Action,
      name: "error_transport_validation",
      schema:
        Zoi.object(%{
          name: Zoi.string(),
          users: Zoi.list(Zoi.object(%{name: Zoi.string()}))
        })

    def run(params, _context), do: {:ok, params}
  end

  describe "transport key policy" do
    test "normalizes absent, scalar and opaque details for JSON transport" do
      for details <- [nil, []] do
        assert Error.to_map(%{message: "failed", details: details}).details == %{}
      end

      assert Error.to_map(%{message: "failed", details: 42}).details == %{value: 42}
      reference = make_ref()

      result =
        Error.to_map(%{message: "failed", details: %{reference: reference, bits: <<1::1>>}})

      assert result.details.reference == inspect(reference)
      assert result.details.bits == "<<1::size(1)>>"
      assert Jason.encode!(result)

      assert Error.to_map(%{message: %{message: 42}}).message == "42"

      assert Error.to_map(%{type: "validation_error", message: "invalid"}).type ==
               :validation_error

      assert Error.to_map(%{"type" => :timeout, "message" => "late"}).type == :timeout

      assert Error.execution_error("failed", details: :invalid, attempt: 3).details == %{
               attempt: 3
             }
    end

    test "retry hints survive transport wrappers and take priority over type defaults" do
      for key <- [:retry, :retryable, :retryable?], hint <- [true, false] do
        error = %{type: :validation_error, details: [{key, hint}]}
        assert Error.retryable?(error) == hint
        assert Error.retryable?({:error, error, [:already_completed]}) == hint
        assert Error.retryable?(%{details: %{details: %{key => hint}}}) == hint
      end

      for hint <- [true, false], key <- [:retryable, "retryable", "retryable?"] do
        assert Error.retryable?(%{key => hint}) == hint
      end

      refute Error.retryable?(%{type: "validation_error"})
      refute Error.retryable?(%{"type" => :config_error})
      refute Error.retryable?(%{"details" => %{"retry" => false}})
      assert Error.retryable?(%{details: %{details: %{unknown: true}}})
      assert Error.retryable?(%{details: [unknown: true]})
      assert Error.retryable?(%{details: [:unknown]})
    end

    test "redacts sensitive keys in maps and key-value lists without changing key names" do
      keys = [
        :api_key,
        "API.KEY",
        "prefixApiKeySuffix",
        :authorization,
        "AUTHORIZATION-header",
        :credential,
        "userCredentials",
        :password,
        "pass / word",
        :private_key,
        "PRIVATE-KEY",
        :secret,
        "clientSecretValue",
        :token,
        "accessToken",
        "to\tken",
        "seécret"
      ]

      for key <- keys, entries <- [%{key => "hidden"}, [{key, "hidden"}]] do
        error = Error.execution_error("Failed", details: %{nested: entries})
        result = Error.to_map(error)

        assert result.details.nested == %{key => "[REDACTED]"}
        assert Jido.Observe.exception_metadata(:error, error).error == result
        refute Jason.encode!(result) =~ "hidden"
      end
    end

    test "redaction takes priority over stacktrace omission" do
      for key <- [:token_stacktrace, "STACK.TRACE-password", "secretStackTrace"],
          entries <- [%{key => <<255>>}, [{key, <<255>>}]] do
        error = Error.execution_error("Failed", details: %{nested: entries})
        assert Error.to_map(error).details.nested == %{key => "[REDACTED]"}
      end
    end

    test "keeps key handling for invalid binaries and non-string map keys" do
      details = %{
        <<255>> => "visible",
        (<<255>> <> "TOKEN") => "hidden",
        {:password, 1} => "hidden",
        123 => "visible"
      }

      error = Error.execution_error("Failed", details: %{nested: details})

      assert Error.to_map(error).details.nested == %{
               <<255>> => "visible",
               (<<255>> <> "TOKEN") => "[REDACTED]",
               "{:password, 1}" => "[REDACTED]",
               "123" => "visible"
             }
    end

    test "omits stacktrace variants and keeps ordinary keys visible" do
      for key <- [
            :stacktrace,
            :stack_trace,
            "StackTrace",
            "call-stack.trace-value",
            "sta ck/trace"
          ] do
        for entries <- [%{key => "hidden"}, [{key, "hidden"}]] do
          error = Error.execution_error("Failed", details: %{nested: entries})
          assert Error.to_map(error).details.nested == %{key => "[OMITTED]"}
        end
      end

      details = %{"api" => 1, "key" => 2, "stack" => 3, "trace" => 4, name: "visible"}
      error = Error.execution_error("Failed", details: %{nested: details})
      assert Error.to_map(error).details.nested == details
    end
  end

  describe "transport boundaries from current main" do
    test "preserves field names and indexes in validation paths" do
      for path <- [[:name], ["name"], [:users, 0, :name], ["users", 19, "name"]] do
        details = %{errors: [%{code: :required, message: "is required", path: path}]}

        for error <- [
              Error.validation_error("Invalid", details: details),
              Jido.Action.Error.validation_error("Invalid", details)
            ] do
          assert Error.to_map(error).details.errors == details.errors
        end
      end
    end

    test "preserves real Zoi validation paths through execution and JSON transport" do
      for {params, path} <- [
            {%{users: []}, [:name]},
            {%{name: "example", users: [%{name: 123}]}, [:users, 0, :name]}
          ] do
        assert {:error, %Jido.Action.Error.InvalidInputError{} = error} =
                 Jido.Exec.run(ValidationAction, params)

        assert [%{path: ^path}] = error.details.errors
        result = Error.to_map(error)
        assert result.details.errors == Jido.Action.Error.to_map(error).details.errors
        assert Jido.Observe.exception_metadata(:error, error).error == result

        encoded_path =
          Enum.map(path, fn part -> if is_atom(part), do: to_string(part), else: part end)

        decoded = result |> Jason.encode!() |> Jason.decode!()
        assert [%{"path" => ^encoded_path}] = decoded["details"]["errors"]
      end
    end

    test "preserves scalar leaves at the container depth limit" do
      values = [nil, true, false, :field, 42, 1.5, "field"]
      error = Error.execution_error("Failed", details: %{a: %{b: %{c: values}}})

      assert Error.to_map(error).details.a.b.c == values
    end

    test "keeps invalid binary leaves safe for JSON transport" do
      error = Error.execution_error("Failed", details: %{a: %{b: %{c: [<<255>>]}}})
      result = Error.to_map(error)

      assert result.details.a.b.c == ["<<255>>"]
      assert Jason.encode!(result)

      metadata = Jido.Observe.exception_metadata(:error, error)
      assert metadata.error == result
      assert Jason.encode!(metadata)
    end

    test "bounds long invalid binaries and redacts them under sensitive keys" do
      for value <- [
            :binary.copy(<<255>>, 2048),
            String.duplicate("x", 700) <> <<255>>,
            <<255>> <> String.duplicate("x", 700)
          ] do
        leaf = %{value: value, password: value}
        error = Error.execution_error("Failed", details: %{a: %{b: %{c: leaf}}})
        result = Error.to_map(error)

        assert result.details.a.b.c.password == "[REDACTED]"
        assert String.valid?(result.details.a.b.c.value)
        assert String.length(result.details.a.b.c.value) <= 512 + String.length("...(truncated)")
        assert Jason.encode!(result)

        metadata = Jido.Observe.exception_metadata(:error, error)
        assert metadata.error == result
        assert Jason.encode!(metadata)
      end
    end

    test "still stops containers and opaque terms at the depth limit" do
      values = [%{value: "hidden"}, ["hidden"], %BadInspect{token: "hidden"}, {:value, "hidden"}]
      error = Error.execution_error("Failed", details: %{a: %{b: %{c: values}}})

      assert Error.to_map(error).details.a.b.c == List.duplicate("[DEPTH_LIMIT]", 4)
    end

    test "still redacts and truncates values at the depth limit" do
      leaf = %{
        password: "hidden-password",
        accessToken: "hidden-token",
        stackTrace: [{__MODULE__, :test, 0, []}],
        text: String.duplicate("x", 700),
        nested: %{value: "hidden"}
      }

      error = Error.execution_error("Failed", details: %{a: [%{b: leaf}]})
      result = Error.to_map(error)

      assert result.details.a == [
               %{
                 b: %{
                   password: "[REDACTED]",
                   accessToken: "[REDACTED]",
                   stackTrace: "[OMITTED]",
                   text: String.duplicate("x", 512) <> "...(truncated)",
                   nested: "[DEPTH_LIMIT]"
                 }
               }
             ]

      refute Jason.encode!(result) =~ "hidden"
    end

    test "still bounds validation error counts and path lengths" do
      errors = List.duplicate(%{path: Enum.to_list(0..24)}, 25)
      error = Error.validation_error("Invalid", details: %{errors: errors})
      result = Error.to_map(error)

      assert result.details.errors == List.duplicate(%{path: Enum.to_list(0..19)}, 20)
    end
  end
end
