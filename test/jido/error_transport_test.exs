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
