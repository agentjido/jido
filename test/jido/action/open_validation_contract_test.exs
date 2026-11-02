defmodule JidoActionTest.OpenValidationContractTest do
  use ExUnit.Case, async: true

  alias Jido.Validation

  defmodule Value do
    defstruct [:count]
  end

  @tag obligation: "jido_action.validation.I1"
  test "open validation modes retain distinct struct results and the same map results" do
    schema = Zoi.struct(Value, %{count: Zoi.integer()}, coerce: true)
    input = %{count: 2, extra: :kept}

    assert {:ok, ^input} = Validation.open_validate(schema, input, %{})

    assert {:ok, %Value{count: 2}} =
             Validation.open_validate_preserving_shape(schema, input, %{})

    for validate <- validators() do
      assert {:ok, ^input} =
               validate.(Zoi.object(%{count: Zoi.integer()}), input, %{})

      assert {:ok, :unchanged} = validate.([], :unchanged, %{})
      assert {:ok, 2} = validate.(Zoi.integer(), 2, %{})
    end
  end

  @tag obligation: "jido_action.validation.I3"
  test "open validation modes return the same complete public parse errors" do
    schema = Zoi.object(%{count: Zoi.integer()})
    details = %{phase: :input, errors: :replaced}
    {:error, errors} = Zoi.parse(schema, %{count: "bad"})

    expected_details = %{
      phase: :input,
      errors: Enum.map(errors, &Map.take(&1, [:path, :message, :code]))
    }

    for validate <- validators() do
      assert {:error, error} = validate.(schema, %{count: "bad"}, details)
      assert %Validation.Error{} = error
      assert error.message == Zoi.prettify_errors(errors)
      assert error.details == expected_details

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
    [&Validation.open_validate/3, &Validation.open_validate_preserving_shape/3]
  end
end
