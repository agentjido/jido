defmodule Jido.Flow.ConditionTest do
  use ExUnit.Case, async: true

  alias Jido.Expr
  alias Jido.Error.ValidationError
  alias Jido.Flow.Ref
  alias Jido.Flow.Value

  describe "condition/2" do
    test "accepts direct Boolean values, references, and Elixir expression operators" do
      assert {:ok, true} = Value.condition(true, :any)
      ref = Ref.input(:enabled)
      assert {:ok, ^ref} = Value.condition(ref, :any)

      for {operator, operands} <- [
            {:==, [Ref.input(:kind), :priority]},
            {:!=, [1, 2]},
            {:<, [1, 2]},
            {:<=, [1, 2]},
            {:>, [2, 1]},
            {:>=, [2, 1]},
            {:in, [1, [1, 2]]},
            {:and, [true, false]},
            {:or, [false, true]},
            {:not, [false]}
          ] do
        expression = Expr.new!(operator, operands)
        assert {:ok, ^expression} = Value.condition(expression, :any)
      end
    end

    test "rejects unknown operators and invalid arity with paths" do
      assert {:error,
              %ValidationError{
                message: "invalid Flow expression",
                details: %{path: [], reason: :unknown_operator}
              }} =
               Value.condition(
                 %Jido.Expr.Operation{operator: :unknown, operands: [1]},
                 :any
               )

      for {operator, operands} <- [
            {:==, [1]},
            {:and, []},
            {:not, [true, false]},
            {:==, [1 | :tail]},
            {:or, [true | :tail]},
            {:==, :bad}
          ] do
        assert {:error, %ValidationError{message: "invalid Flow expression", details: details}} =
                 Value.condition(
                   %Jido.Expr.Operation{operator: operator, operands: operands},
                   :any
                 )

        assert details.reason == :invalid_arity
        assert details.operator == operator
        assert details.path == []
      end
    end

    test "rejects malformed refs, structs, and functions with expression paths" do
      assert {:error, %ValidationError{message: message, details: details}} =
               Value.condition(
                 %Jido.Expr.Operation{
                   operator: :==,
                   operands: [Ref.input([%{bad: :segment}]), 1]
                 },
                 :any
               )

      assert message == "flow expression contains an invalid reference path"
      assert details.path == [:operands, 0]

      assert {:error, %ValidationError{message: message, details: details}} =
               Value.condition(Expr.new!(:==, [~D[2026-01-01], 1]), :any)

      assert message == "flow expression contains an unsupported value"
      assert details.path == [:operands, 0]
      assert details.expression == Date

      assert {:error, %ValidationError{message: message, details: details}} =
               Value.condition(Expr.new!(:==, [fn -> :predicate end, 1]), :any)

      assert message == "invalid Flow expression"
      assert details.path == [:operands, 0]
      assert details.reason == :unsupported_value
    end

    test "rejects non-Boolean literal condition forms" do
      assert {:error, %ValidationError{}} = Value.condition(:bad, :any)
      assert {:error, %ValidationError{}} = Value.condition(%{}, :any)
    end
  end

  test "collects result dependencies from nested Boolean operands" do
    condition =
      Expr.new!(:and, [
        Expr.new!(:==, [Ref.result(:classify, :kind), :priority]),
        Expr.new!(:or, [
          Expr.new!(:in, [Ref.result(:load_tags), ["bulk", "archive"]]),
          Expr.new!(:not, [Expr.new!(:!=, [Ref.result(:classify, :source), "api"])])
        ])
      ])

    assert condition |> Value.result_refs() |> Enum.uniq() |> Enum.sort() == [
             "classify",
             "load_tags"
           ]
  end
end
