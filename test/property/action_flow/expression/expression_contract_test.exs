Code.require_file("../../support/fuzz.exs", __DIR__)

defmodule JidoTest.Property.ActionFlow.Expression.ExpressionContractTest do
  use Covenant.Case, component: "jido_action.expression", async: true
  use ExUnitProperties
  alias JidoTest.Property.Fuzz
  alias Jido.Expr

  @tag :fuzz
  @tag fuzz_id: "expression_trees"
  @tag max_runs: 1_000, max_run_time: 300_000, timeout: 900_000
  @tag obligation: [
         "jido_action.expression.I1",
         "jido_action.expression.I2",
         "jido_action.expression.I4"
       ]
  test "fuzz: expression trees agree with native operations and enforce limits", context do
    generator =
      fixed_map(%{"tree" => one_of([number_tree(5), boolean_tree(2)]), "size" => integer(5..128)})

    Fuzz.check("expression_trees", generator, Map.to_list(context), fn sample ->
      {expression, expected, depth} = expression(sample["tree"])

      expression =
        cond do
          is_struct(expression, Jido.Expr.Operation) -> expression
          is_boolean(expression) -> Expr.new!(:or, [false, expression])
          true -> Expr.new!(:+, [0, expression])
        end

      assert Expr.evaluate(expression) == {:ok, expected}
      size = sample["size"]
      bad = Expr.new!(:/, [size, 0])
      assert Expr.evaluate(Expr.new!(:and, [false, bad])) == {:ok, false}
      assert Expr.evaluate(Expr.new!(:or, [true, bad])) == {:ok, true}
      assert {:error, %Expr.Error{}} = Expr.evaluate(Expr.new!(:+, ["invalid", expression]))

      for {value, limits} <- [
            {String.duplicate("x", size), [max_binary_bytes: size - 1]},
            {Integer.pow(2, size), [max_integer_bits: size]},
            {List.duplicate(0, size), [max_nodes: size - 1]},
            {Enum.reduce(1..size, 0, fn _, acc -> [acc] end), [max_depth: size - 1]}
          ] do
        expression = Expr.new!(:==, [value, value])
        assert {:error, %Expr.Error{}} = Expr.validate(expression, limits)
        assert {:error, %Expr.Error{}} = Expr.evaluate(expression, limits)
      end

      for {operator, _arity} <- Expr.operations(),
          do: assert({:error, %Expr.Error{}} = Expr.new(operator, []))

      assert {:error, %Expr.Error{}} = Expr.parse(quote do: send(self(), unquote(size)))
      refute_received ^size
      ["depth:#{depth}", if(is_boolean(expected), do: "boolean", else: "number")]
    end)
  end

  defp number_tree(0), do: integer(-50..50)

  defp number_tree(depth) do
    one_of([
      number_tree(0),
      fixed_map(%{
        "op" => member_of(["+", "-", "*", "min", "max"]),
        "left" => number_tree(depth - 1),
        "right" => number_tree(depth - 1)
      })
    ])
  end

  defp boolean_tree(0) do
    one_of([
      boolean(),
      fixed_map(%{
        "op" => member_of(["==", "<", ">="]),
        "left" => number_tree(3),
        "right" => number_tree(3)
      })
    ])
  end

  defp boolean_tree(depth) do
    one_of([
      boolean_tree(0),
      fixed_map(%{
        "op" => member_of(~w(and or)),
        "left" => boolean_tree(depth - 1),
        "right" => boolean_tree(depth - 1)
      })
    ])
  end

  defp expression(%{"op" => op, "left" => left, "right" => right}) do
    {left_expr, a, left_depth} = expression(left)
    {right_expr, b, right_depth} = expression(right)

    {operator, value} =
      case op do
        "+" -> {:+, a + b}
        "-" -> {:-, a - b}
        "*" -> {:*, a * b}
        "min" -> {:min, min(a, b)}
        "max" -> {:max, max(a, b)}
        "==" -> {:==, a == b}
        "<" -> {:<, a < b}
        ">=" -> {:>=, a >= b}
        "and" -> {:and, a and b}
        "or" -> {:or, a or b}
      end

    {Expr.new!(operator, [left_expr, right_expr]), value, max(left_depth, right_depth) + 1}
  end

  defp expression(value), do: {value, value, 0}

  @tag obligation: "jido_action.expression.I1"
  property "the fixed operator set agrees with native Elixir for generated operands" do
    check all(left <- integer(-100..100), right <- integer(1..100), max_runs: 60) do
      cases = [
        {:+, [left, right], left + right},
        {:-, [left, right], left - right},
        {:*, [left, right], left * right},
        {:/, [left, right], left / right},
        {:div, [left, right], div(left, right)},
        {:rem, [left, right], rem(left, right)},
        {:-, [left], -left},
        {:abs, [left], abs(left)},
        {:min, [left, right], min(left, right)},
        {:max, [left, right], max(left, right)},
        {:==, [left, right], left == right},
        {:!=, [left, right], left != right},
        {:<, [left, right], left < right},
        {:<=, [left, right], left <= right},
        {:>, [left, right], left > right},
        {:>=, [left, right], left >= right},
        {:in, [left, [right, left]], true},
        {:in, [left, [left * 1.0]], false},
        {:<>, [Integer.to_string(left), Integer.to_string(right)], Integer.to_string(left) <> Integer.to_string(right)}
      ]

      for {operator, operands, expected} <- cases do
        expression = Expr.new!(operator, operands)
        assert :ok = Expr.validate(expression)
        assert Expr.evaluate(expression) == {:ok, expected}
      end

      ast = quote do: (unquote(left) + unquote(right)) * unquote(right)
      assert {:ok, parsed} = Expr.parse(ast)
      assert Expr.evaluate(parsed) == {:ok, (left + right) * right}
    end
  end

  @tag obligation: "jido_action.expression.I1"
  property "Boolean operations short-circuit invalid branches and retain their result rules" do
    check all(value <- integer(), max_runs: 40) do
      invalid = Expr.new!(:/, [value, 0])

      for {operator, operands, expected} <- [
            {:and, [false, invalid], false},
            {:or, [true, invalid], true},
            {:and, [true, value], value},
            {:or, [false, value], value},
            {:not, [true], false},
            {:not, [false], true}
          ] do
        assert Expr.evaluate(Expr.new!(operator, operands)) == {:ok, expected}
      end

      for operator <- [:and, :or] do
        assert {:error, %Expr.Error{}} = Expr.evaluate(Expr.new!(operator, [value, true]))
      end

      assert {:error, %Expr.Error{}} = Expr.evaluate(invalid)
    end
  end

  @tag obligation: "jido_action.expression.I4"
  property "public limits reject oversized data and constructors reject unsupported operations" do
    check all(size <- integer(5..16), max_runs: 30) do
      for {value, options} <- [
            {String.duplicate("x", size), [max_binary_bytes: size - 1]},
            {Integer.pow(2, size), [max_integer_bits: size]},
            {List.duplicate(0, size), [max_nodes: size - 1]},
            {Enum.reduce(1..size, 0, fn _, value -> [value] end), [max_depth: size - 1]}
          ] do
        expression = Expr.new!(:==, [value, value])
        assert {:error, %Expr.Error{}} = Expr.validate(expression, options)
        assert {:error, %Expr.Error{}} = Expr.evaluate(expression, options)
      end

      for {operator, _arity} <- Expr.operations() do
        assert {:error, %Expr.Error{}} = Expr.new(operator, [])
      end

      assert {:error, %Expr.Error{}} = Expr.new("unknown_#{size}", [1, 2])

      assert {:error, %Expr.Error{}} =
               Expr.parse(quote do: System.get_env(unquote(Integer.to_string(size))))
    end
  end
end
