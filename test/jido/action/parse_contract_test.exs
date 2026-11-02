defmodule JidoActionTest.Action.ParseContractTest do
  use Covenant.Case, component: "jido_action.validation", async: true

  alias Jido.Action.Error
  alias Jido.Action.Validation

  defmodule Value do
    defstruct [:count, :tag]
  end

  @tag obligation: "jido_action.validation.I1"
  test "parse modes retain distinct struct shapes and the same Zoi field policy" do
    schema = Zoi.struct(Value, %{count: Zoi.integer()}, coerce: true)
    input = %{count: 2, extra: :kept}

    assert {:ok, %{count: 2, tag: nil}} = Validation.parse(schema, input, %{})

    assert {:ok, %Value{count: 2, tag: nil}} =
             Validation.parse_preserving_shape(schema, input, %{})

    assert {:ok, %{count: 2, tag: nil}} =
             Validation.parse(Zoi.nullable(schema), input, %{})

    for validate <- validators() do
      assert {:ok, %{count: 2}} =
               validate.(Zoi.object(%{count: Zoi.integer()}), input, %{})

      assert {:error, %{message: "Unsupported schema type"}} = validate.([], :unchanged, %{})
      assert {:ok, 2} = validate.(Zoi.integer(), 2, %{})
    end
  end

  @tag obligation: "jido_action.validation.I3"
  test "parse modes return the same complete public parse errors" do
    schema = Zoi.object(%{count: Zoi.integer()})
    details = %{phase: :input, errors: :replaced}
    {:error, errors} = Zoi.parse(schema, %{count: "bad"})

    expected =
      Error.validation_error(
        Zoi.prettify_errors(errors),
        %{phase: :input, errors: Enum.map(errors, &Map.take(&1, [:path, :message, :code]))}
      )
      |> Error.to_map()

    for validate <- validators() do
      assert {:error, error} = validate.(schema, %{count: "bad"}, details)
      assert Error.to_map(error) == expected

      assert {:error, error} = validate.(:unsupported, %{}, details)
      assert error.message == "Unsupported schema type"
      assert error.details == details
    end
  end

  @tag obligation: "jido_action.validation.I3"
  test "both modes contain raised, thrown, and exited schema failures" do
    cases = [
      {fn -> raise "schema failed" end, %{exception: RuntimeError, reason: "schema failed"}},
      {fn -> throw(:schema_failed) end, %{failure_kind: :throw, reason: ":schema_failed"}},
      {fn -> exit(:schema_failed) end, %{failure_kind: :exit, reason: ":schema_failed"}}
    ]

    for validate <- validators(), {failure, expected} <- cases do
      assert {:error, error} = validate.(Zoi.lazy(failure), %{}, %{phase: :input})
      assert error.message == "schema validation failed"
      assert error.details == Map.put(expected, :phase, :input)
    end
  end

  defp validators do
    [&Validation.parse/3, &Validation.parse_preserving_shape/3]
  end
end
