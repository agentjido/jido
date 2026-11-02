defmodule Jido.ExprTest do
  use Covenant.Case, component: "jido_action.expression", async: true

  alias Jido.Expr
  import Jido.Expr, only: [expr: 1]

  defmodule Reference do
    defstruct [:key]
  end

  @tag obligation: "jido_action.expression.I4"
  test "documented default limits admit the boundary and reject the next value" do
    # Root expression, list operand, items and right operand total 10_000 nodes.
    assert :ok = Expr.validate(Expr.new!(:==, [List.duplicate(0, 9_997), nil]))

    assert {:error, %Expr.Error{reason: :max_nodes}} =
             Expr.validate(Expr.new!(:==, [List.duplicate(0, 9_998), nil]))

    assert :ok = Expr.validate(Expr.new!(:==, [nest(0, 63), nil]))

    assert {:error, %Expr.Error{reason: :max_depth}} =
             Expr.validate(Expr.new!(:==, [nest(0, 64), nil]))

    assert :ok = Expr.validate(Expr.new!(:==, [String.duplicate("x", 1_048_576), nil]))

    assert {:error, %Expr.Error{reason: :max_binary_bytes}} =
             Expr.validate(Expr.new!(:==, [String.duplicate("x", 1_048_577), nil]))

    bound = Integer.pow(2, 4_096)

    for value <- [bound - 1, -bound + 1],
        do: assert(:ok = Expr.validate(Expr.new!(:+, [value, 0])))

    for value <- [bound, -bound] do
      assert {:error, %Expr.Error{reason: :max_integer_bits}} =
               Expr.validate(Expr.new!(:+, [value, 0]))
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "constructs and evaluates a portable calculation" do
    assert {:ok, expression} = Jido.Expr.new(:+, [2, 3])
    assert {:ok, 5} = Jido.Expr.evaluate(expression)
  end

  @tag obligation: "jido_action.expression.I2"
  test "standalone macro inserts a prebuilt reference through an explicit variable pin" do
    reference = %Reference{key: :count}
    expression = expr(^reference * 2 + 1)

    assert {:ok, 9} = Jido.Expr.evaluate(expression, resolve: fn ^reference -> {:ok, 4} end)
    assert {:ok, 7} = Jido.Expr.evaluate(expr(2 * 3 + 1))

    for source <- [
          quote(do: Jido.Expr.expr(^System.unique_integer())),
          quote(do: Jido.Expr.expr(value)),
          quote(do: Jido.Expr.expr(System.unique_integer()))
        ] do
      assert_raise Jido.Expr.Error, fn -> Macro.expand_once(source, __ENV__) end
    end
  end

  @tag obligation: "jido_action.expression.I3"
  test "host callback errors retain their expression path" do
    reference = %Reference{key: :count}
    expression = Jido.Expr.new!(:+, [Jido.Expr.new!(:+, [reference, 1]), 2])
    reference_path = [:operands, 0, :operands, 0]
    host_error = %Jido.Expr.Error{reason: :missing_field, path: [:field, 2]}
    expected = %{host_error | path: reference_path ++ [:field, 2]}

    for callback <- [
          fn ^reference -> {:error, host_error} end,
          fn ^reference, path ->
            assert path == reference_path
            {:error, host_error}
          end
        ] do
      assert {:error, ^expected} = Jido.Expr.evaluate(expression, resolve: callback)
      assert {:error, ^expected} = Jido.Expr.validate(expression, validate_leaf: callback)
    end

    assert {:error, %Jido.Expr.Error{reason: :callback_failure, path: ^reference_path}} =
             Jido.Expr.evaluate(expression, resolve: fn _ -> raise "private" end)
  end

  @tag obligation: "jido_action.expression.I1"
  test "the complete operation set follows Elixir operator names" do
    cases = [
      {:==, [1, 1.0], true},
      {:!=, [1, 1.0], false},
      {:<, [1, 2], true},
      {:<=, [2, 2], true},
      {:>, ["b", "a"], true},
      {:>=, [2.0, 2], true},
      {:in, [1, [2, 1.0]], false},
      {:and, [true, 123], 123},
      {:or, [false, "fallback"], "fallback"},
      {:not, [false], true},
      {:+, [1, 2.5], 3.5},
      {:-, [4, 6], -2},
      {:-, [2], -2},
      {:*, [3, 2.0], 6.0},
      {:/, [3, 2], 1.5},
      {:div, [-7, 3], -2},
      {:rem, [-7, 3], -1},
      {:min, [1, 1.0], 1},
      {:max, [1.0, 1], 1.0},
      {:abs, [-2.5], 2.5},
      {:<>, ["hello", "!"], "hello!"}
    ]

    actual_operations =
      Enum.map(cases, fn {operator, operands, _} -> {operator, length(operands)} end)

    assert Enum.sort(actual_operations) == Enum.sort(Jido.Expr.operations())

    for {operator, operands, expected} <- cases do
      assert {:ok, actual} = Jido.Expr.evaluate(Jido.Expr.new!(operator, operands))
      assert actual === expected
    end
  end

  @tag obligation: "jido_action.expression.I2"
  test "rejects unknown operators and incorrect arity" do
    for {operator, operands, reason} <- [
          {:custom, [], :unknown_operator},
          {:all, [true], :unknown_operator},
          {:any, [false], :unknown_operator},
          {:not, [], :invalid_arity},
          {:+, [1], :invalid_arity},
          {:and, [true | false], :invalid_arity}
        ] do
      assert {:error, %Jido.Expr.Error{reason: ^reason}} = Jido.Expr.new(operator, operands)
      assert_raise Jido.Expr.Error, fn -> Jido.Expr.new!(operator, operands) end
    end
  end

  @tag obligation: "jido_action.expression.I4"
  test "fixed arities reject oversized operand lists with bounded work" do
    operands = List.duplicate(1, 1_000_000)
    improper_operands = [1 | operands] ++ :invalid_tail

    for values <- [operands, improper_operands] do
      expression = %Jido.Expr{operator: :+, operands: values}

      for check <- [
            fn -> Jido.Expr.new(:+, values) end,
            fn -> Jido.Expr.validate(expression, max_nodes: 1) end,
            fn -> Jido.Expr.evaluate(expression, max_nodes: 1) end,
            fn -> Jido.Expr.normalize(expression, max_nodes: 1) end,
            fn ->
              Jido.Expr.reduce(
                expression,
                nil,
                fn _value, accumulator ->
                  {:cont, accumulator}
                end,
                max_nodes: 1
              )
            end
          ] do
        {result, reductions} = with_reductions(check)
        assert {:error, %Jido.Expr.Error{reason: :invalid_arity, operator: :+}} = result
        assert reductions < 10_000
      end
    end

    for {operator, values} <- [{:not, [true, false]}, {:+, [1]}, {:-, []}, {:-, [1, 2, 3]}] do
      assert {:error, %Jido.Expr.Error{reason: :invalid_arity}} =
               Jido.Expr.new(operator, values)
    end

    assert {:ok, %Jido.Expr{}} = Jido.Expr.new(:-, [1])
    assert {:ok, %Jido.Expr{}} = Jido.Expr.new(:-, [1, 2])
  end

  @tag obligation: "jido_action.expression.I1"
  test "strict type and arithmetic failures contain no runtime values" do
    for {operator, operands, reason} <- [
          {:not, [1], :invalid_boolean_operand},
          {:in, [1, %{secret: "private"}], :invalid_membership_right_operand},
          {:+, ["private", 1], :invalid_numeric_operands},
          {:div, [2.0, 1], :invalid_numeric_operands},
          {:<>, ["private", nil], :invalid_binary_operands},
          {:/, [2, 0], :division_by_zero},
          {:rem, [2, 0], :division_by_zero},
          {:*, [1.0e308, 1.0e308], :arithmetic_error}
        ] do
      assert {:error, %Jido.Expr.Error{reason: ^reason, operator: ^operator} = error} =
               Jido.Expr.evaluate(Jido.Expr.new!(operator, operands))

      refute inspect(error.details) =~ "private"
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "strict binary operators reject invalid types on either side" do
    for {operators, invalid, valid, reason} <- [
          {[:+, :-, :*, :/], "private", 1, :invalid_numeric_operands},
          {[:div, :rem], 1.0, 1, :invalid_numeric_operands},
          {[:<>], nil, "private", :invalid_binary_operands}
        ],
        operator <- operators,
        operands <- [[invalid, valid], [valid, invalid]] do
      assert {:error, %Jido.Expr.Error{reason: ^reason, operator: ^operator} = error} =
               Jido.Expr.evaluate(Jido.Expr.new!(operator, operands))

      refute inspect(error) =~ "private"
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "numeric operators handle zero and reject every zero divisor" do
    for {operator, operands, expected} <- [
          {:+, [0, 0], 0},
          {:-, [0, 0], 0},
          {:*, [0, -3], 0},
          {:/, [0, -3], -0.0},
          {:-, [0], 0},
          {:div, [0, -3], 0},
          {:rem, [0, -3], 0},
          {:min, [0, 1], 0},
          {:max, [-1, 0], 0},
          {:abs, [0], 0}
        ] do
      assert {:ok, actual} = Jido.Expr.evaluate(Jido.Expr.new!(operator, operands))
      assert actual === expected
    end

    for {operator, divisors} <- [{:/, [0, 0.0, -0.0]}, {:div, [0]}, {:rem, [0]}],
        divisor <- divisors,
        numerator <- [0, 2, -2] do
      assert {:error, %Jido.Expr.Error{reason: :division_by_zero, operator: ^operator}} =
               Jido.Expr.evaluate(Jido.Expr.new!(operator, [numerator, divisor]))
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "binary Boolean operations short-circuit like Elixir" do
    reference = %Reference{key: :missing}
    resolver = fn _ -> flunk("skipped operand must not resolve") end

    assert {:ok, false} =
             Jido.Expr.evaluate(Jido.Expr.new!(:and, [false, reference]), resolve: resolver)

    assert {:ok, true} =
             Jido.Expr.evaluate(Jido.Expr.new!(:or, [true, reference]), resolve: resolver)

    assert {:error, %Jido.Expr.Error{reason: :unsupported_value, path: [:operands, 1]}} =
             Jido.Expr.validate(Jido.Expr.new!(:and, [false, reference]))

    assert :ok =
             Jido.Expr.validate(Jido.Expr.new!(:and, [false, reference]),
               validate_leaf: fn ^reference -> :ok end
             )
  end

  @tag obligation: "jido_action.expression.I2"
  test "shared parser supports the Elixir subset and precedence" do
    cases = [
      {quote(do: 1 + 2 * 3), 7},
      {quote(do: -(2 - 5)), 3},
      {quote(do: div(-7, 3)), -2},
      {quote(do: rem(-7, 3)), -1},
      {quote(do: min(2, max(1, abs(-3)))), 2},
      {quote(do: 3 / 2), 1.5},
      {quote(do: "a" <> "b" <> "c"), "abc"},
      {quote(do: (1 == 1.0 and not false) or false), true},
      {quote(do: 2 != 3 and 2 < 3 and 2 <= 2 and 3 > 2 and 3 >= 3), true},
      {quote(do: 1 in [1.0, 2]), false}
    ]

    for {ast, expected} <- cases do
      assert {:ok, expression} = Jido.Expr.parse(ast)
      assert {:ok, actual} = Jido.Expr.evaluate(expression)
      assert actual === expected
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "a host DSL supplies reference leaves without changing the grammar" do
    parser = fn
      {:field, _, [key]} when is_atom(key) -> {:ok, %Reference{key: key}}
      _ -> :error
    end

    expression =
      Jido.Expr.parse!(quote(do: field(:count) * 2 >= 8 and not field(:paused)),
        leaf_parser: parser
      )

    values = %{count: 4, paused: false}

    assert {:ok, true} =
             Jido.Expr.evaluate(expression,
               resolve: fn %Reference{key: key}, path ->
                 assert :operands in path
                 Map.fetch(values, key)
               end
             )

    assert :ok =
             Jido.Expr.validate(expression,
               validate_leaf: fn %Reference{}, path ->
                 assert :operands in path
                 :ok
               end
             )
  end

  @tag obligation: "jido_action.expression.I2"
  test "parser rejects general Elixir, aliases, and non-expression roots" do
    for ast <- [
          quote(do: System.unique_integer()),
          quote(do: value),
          quote(do: x = 1),
          quote(do: 1 |> abs()),
          quote(do: fn -> 1 end),
          quote(do: ^value),
          quote(do: 1 && 2),
          quote(do: false || true),
          quote(do: !false),
          quote(do: 1 === 1),
          quote(do: 1 !== 1),
          quote(do: 1 ** 2),
          quote(do: round(1.2)),
          quote(do: eq(1, 1)),
          quote(do: gte(2, 1)),
          quote(do: all([true, false])),
          quote(do: any([false, true])),
          quote(do: [key: 1]),
          quote(do: {1, 2}),
          quote(do: [1, 2]),
          quote(do: %{key: 1})
        ] do
      assert {:error, %Jido.Expr.Error{}} = Jido.Expr.parse(ast)
      assert_raise Jido.Expr.Error, fn -> Jido.Expr.parse!(ast) end
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "resolved expression-shaped data is not executed" do
    data = Jido.Expr.new!(:/, [1, 0])
    left = %Reference{key: :left}
    right = %Reference{key: :right}

    assert {:ok, true} =
             Jido.Expr.evaluate(Jido.Expr.new!(:==, [left, right]),
               resolve: fn reference when reference in [left, right] -> {:ok, data} end
             )
  end

  @tag obligation: "jido_action.expression.I4"
  test "limits cover expression operands, resolved data, generated output, and comparison work" do
    deep = Enum.reduce(1..8, 0, fn _, child -> [child] end)

    assert {:error, %Jido.Expr.Error{reason: :max_depth}} =
             Jido.Expr.validate(Jido.Expr.new!(:==, [deep, deep]), max_depth: 4)

    assert {:error, %Jido.Expr.Error{reason: :max_binary_bytes}} =
             Jido.Expr.evaluate(Jido.Expr.new!(:<>, ["abc", "def"]), max_binary_bytes: 8)

    assert {:error, %Jido.Expr.Error{reason: :max_integer_bits}} =
             Jido.Expr.evaluate(Jido.Expr.new!(:*, [16, 16]), max_integer_bits: 8)

    reference = %Reference{}

    assert {:error, %Jido.Expr.Error{reason: :max_nodes}} =
             Jido.Expr.evaluate(Jido.Expr.new!(:==, [reference, []]),
               resolve: fn _ -> {:ok, Enum.to_list(1..10)} end,
               max_nodes: 5
             )

    assert {:error, %Jido.Expr.Error{reason: :max_depth}} =
             Jido.Expr.parse(quote(do: 1 + [[[2 + 3]]]), max_depth: 2)
  end

  @tag obligation: "jido_action.expression.I4"
  test "resolved large data stops within the node work limit" do
    reference = %Reference{}
    expression = Jido.Expr.new!(:==, [reference, nil])

    for value <- [Map.new(1..100_000, &{&1, &1}), :erlang.make_tuple(100_000, nil)] do
      {result, reductions} =
        with_reductions(fn ->
          Jido.Expr.evaluate(expression, resolve: fn _ -> {:ok, value} end, max_nodes: 2)
        end)

      assert {:error, %Jido.Expr.Error{reason: :max_nodes}} = result
      assert reductions < 10_000
    end
  end

  @tag obligation: "jido_action.expression.I4"
  test "membership preserves cumulative budgets and the first failing data path" do
    left = %{items: ["abc", 1]}
    right = [%{items: ["xyz", 1]}, %{items: ["abc", 1.0]}]
    expression = Jido.Expr.new!(:in, [left, right])

    for {options, reason, path, operator} <- [
          {[max_nodes: 28], :max_nodes, [], nil},
          {[max_nodes: 30], :max_nodes, [0], nil},
          {[max_nodes: 31], :max_nodes, [1], nil},
          {[max_nodes: 37], :max_nodes, [], :in},
          {[max_binary_bytes: 18], :max_binary_bytes, [0], nil}
        ] do
      assert {:error, %Jido.Expr.Error{reason: ^reason, path: ^path, operator: ^operator}} =
               Jido.Expr.evaluate(expression, options)
    end

    assert {:ok, false} = Jido.Expr.evaluate(expression, max_nodes: 38, max_binary_bytes: 21)
  end

  @tag obligation: "jido_action.expression.I3"
  test "invalid options and invalid host callbacks return structured errors" do
    expression = Jido.Expr.new!(:not, [%Reference{}])

    for options <- [
          [unknown: true],
          [max_depth: 0],
          [max_nodes: -1],
          [max_integer_bits: nil],
          [:bad],
          [resolve: :bad]
        ] do
      assert {:error, %Jido.Expr.Error{reason: :invalid_options}} =
               Jido.Expr.evaluate(expression, options)
    end

    assert {:error, %Jido.Expr.Error{reason: :invalid_callback_return}} =
             Jido.Expr.evaluate(expression, resolve: fn _ -> :bad end)

    assert {:error, %Jido.Expr.Error{reason: :callback_failure}} =
             Jido.Expr.evaluate(expression, resolve: fn _ -> raise "private" end)

    assert {:error, :host_error} =
             Jido.Expr.evaluate(expression, resolve: fn _ -> {:error, :host_error} end)
  end

  @tag obligation: "jido_action.expression.I3"
  test "ingress normalization visits host values once and never executes operations" do
    tag = make_ref()
    legacy = %Reference{key: :legacy}
    leaf = %Reference{key: :leaf}

    replacement =
      Jido.Expr.new!(:and, [
        false,
        Jido.Expr.new!(:and, [Jido.Expr.new!(:/, [1, 0]), leaf])
      ])

    assert {:ok, ^replacement} =
             Jido.Expr.normalize(legacy,
               normalize_leaf: fn value, path ->
                 send(self(), {tag, :normalize, value.key, path})
                 {:ok, if(value == legacy, do: replacement, else: value)}
               end,
               validate_leaf: fn value, path ->
                 send(self(), {tag, :validate, value.key, path})
                 :ok
               end
             )

    leaf_path = [:operands, 1, :operands, 1]
    assert_received {^tag, :normalize, :legacy, []}
    assert_received {^tag, :normalize, :leaf, ^leaf_path}
    assert_received {^tag, :validate, :leaf, ^leaf_path}
    refute_received {^tag, _, _, _}
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "normalization checks replacement scalar limits at their exact paths" do
    reference = %Reference{key: :value}

    for {replacement, options, reason} <- [
          {"abcde", [max_binary_bytes: 4], :max_binary_bytes},
          {16, [max_integer_bits: 4], :max_integer_bits},
          {-16, [max_integer_bits: 4], :max_integer_bits}
        ],
        {value, path} <- [{reference, []}, {%{nested: [reference]}, [:nested, 0]}] do
      options = Keyword.put(options, :normalize_leaf, fn ^reference -> {:ok, replacement} end)

      assert {:error, %Jido.Expr.Error{reason: ^reason, path: ^path}} =
               Jido.Expr.normalize(value, options)
    end
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "normalization counts replacement bytes cumulatively and each node once" do
    tag = make_ref()
    first = %Reference{key: :first}
    second = %Reference{key: :second}

    normalize = fn reference, path ->
      send(self(), {tag, reference.key, path})
      {:ok, "abc"}
    end

    assert {:ok, ["abc", "abc"]} =
             Jido.Expr.normalize([first, second],
               normalize_leaf: normalize,
               max_nodes: 3,
               max_binary_bytes: 6
             )

    assert_received {^tag, :first, [0]}
    assert_received {^tag, :second, [1]}
    refute_received {^tag, _, _}

    assert {:error, %Jido.Expr.Error{reason: :max_binary_bytes, path: [1]}} =
             Jido.Expr.normalize([first, second],
               normalize_leaf: normalize,
               max_binary_bytes: 5
             )
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "normalization does not call a host callback after a limit is exhausted" do
    reference = %Reference{key: :value}
    tag = make_ref()

    for {value, options, reason, path} <- [
          {[0, reference], [max_nodes: 2], :max_nodes, [1]},
          {[[[reference]]], [max_depth: 2], :max_depth, [0, 0, 0]},
          {["abc", reference], [max_binary_bytes: 2], :max_binary_bytes, [0]},
          {[16, reference], [max_integer_bits: 4], :max_integer_bits, [0]}
        ] do
      normalize = fn _ ->
        send(self(), tag)
        {:ok, 1}
      end

      assert {:error, %Jido.Expr.Error{reason: ^reason, path: ^path}} =
               Jido.Expr.normalize(value, Keyword.put(options, :normalize_leaf, normalize))

      refute_received ^tag
    end
  end

  @tag obligation: "jido_action.expression.I3"
  test "bounded reduction visits expressions, containers, and host leaves with exact paths" do
    reference = %Reference{key: :count}
    expression = Jido.Expr.new!(:+, [reference, 2])
    value = %{outer: [expression, %{done: true}]}

    assert {:ok, visited} =
             Jido.Expr.reduce(value, [], fn value, path, visited ->
               {:cont, [{value, path} | visited]}
             end)

    assert Enum.any?(visited, fn {value, path} ->
             is_struct(value, Jido.Expr) and path == [:outer, 0]
           end)

    assert {reference, [:outer, 0, :operands, 0]} in visited
    assert {2, [:outer, 0, :operands, 1]} in visited
    assert {true, [:outer, 1, :done]} in visited

    assert {:ok, :found} =
             Jido.Expr.reduce([reference, fn -> :unreachable end], :missing, fn
               ^reference, _path, _accumulator -> {:halt, :found}
               _value, _path, accumulator -> {:cont, accumulator}
             end)

    assert {:error, %Jido.Expr.Error{reason: :max_nodes, path: [:outer]}} =
             Jido.Expr.reduce(
               %{outer: [1, 2]},
               nil,
               fn _value, accumulator ->
                 {:cont, accumulator}
               end,
               max_nodes: 1
             )

    assert {:error, %Jido.Expr.Error{reason: :improper_list, path: [1]}} =
             Jido.Expr.reduce([1 | 2], nil, fn _value, accumulator ->
               {:cont, accumulator}
             end)

    assert {:error, %Jido.Expr.Error{reason: :invalid_reducer}} =
             Jido.Expr.reduce(1, nil, :invalid)

    assert {:error, %Jido.Expr.Error{reason: :invalid_reducer_return}} =
             Jido.Expr.reduce(1, nil, fn _value, _accumulator -> :invalid end)

    assert {:error, %Jido.Expr.Error{reason: :reducer_failure}} =
             Jido.Expr.reduce(1, nil, fn _value, _accumulator -> raise "private" end)
  end

  defp with_reductions(function) do
    Jido.Expr.evaluate(Jido.Expr.new!(:+, [1, 1]))
    Jido.Expr.parse(quote(do: 1 + 1))
    :erlang.garbage_collect()
    {:reductions, before_count} = Process.info(self(), :reductions)
    result = function.()
    {:reductions, after_count} = Process.info(self(), :reductions)
    {result, after_count - before_count}
  end

  defp nest(value, depth), do: Enum.reduce(1..depth, value, fn _, value -> [value] end)
end
