defmodule Jido.Action.ParseContractTest do
  use Covenant.Case, component: "jido_action.validation", async: true

  alias Jido.Error
  alias Jido.Action.Validation

  defmodule Value do
    defstruct [:count, :tag]
  end

  @tag obligation: "jido_action.validation.I1"
  test "parse modes retain distinct struct shapes and open map fields" do
    schema = Jido.Joi.struct(Value, %{count: Jido.Joi.integer()}, coerce: true)
    input = %{count: 2}

    assert {:ok, %{count: 2, tag: nil}} = Validation.parse(schema, input, %{})

    assert {:ok, %Value{count: 2, tag: nil}} =
             Validation.parse_preserving_shape(schema, input, %{})

    assert {:ok, %{count: 2, tag: nil}} =
             Validation.parse(Jido.Joi.nullable(schema), input, %{})

    for validate <- validators() do
      open_input = %{count: 2, extra: :kept}

      assert validate.(Jido.Joi.object(%{count: Jido.Joi.integer()}), open_input, %{}) ==
               {:ok, open_input}

      assert {:error, %{message: "Unsupported schema type"}} = validate.([], :unchanged, %{})
      assert {:ok, 2} = validate.(Jido.Joi.integer(), 2, %{})
    end
  end

  @tag obligation: "jido_action.validation.I3"
  test "parse modes return the same complete public parse errors" do
    schema = Jido.Joi.object(%{count: Jido.Joi.integer()})
    details = %{phase: :input, errors: :replaced}
    {:error, errors} = Jido.Joi.parse(schema, %{count: "bad"})

    expected =
      Error.validation_error(
        Jido.Joi.prettify_errors(errors),
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
      assert {:error, error} = validate.(Jido.Joi.lazy(failure), %{}, %{phase: :input})
      assert error.message == "schema validation failed"
      assert error.details == Map.put(expected, :phase, :input)
    end
  end

  defp validators do
    [&Validation.parse/3, &Validation.parse_preserving_shape/3]
  end
end
