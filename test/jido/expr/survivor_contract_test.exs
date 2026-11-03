defmodule Jido.Expr.SurvivorContractTest do
  use Covenant.Case, component: "jido_action.expression", async: true

  alias Jido.Expr

  defmodule Reference do
    defstruct [:key]
  end

  @tag obligation: "jido_action.expression.I1"
  test "expression literals require both fields before entering the runtime" do
    for ast <- [
          quote(do: %Jido.Expr.Operation{operator: :not}),
          quote(do: %Jido.Expr.Operation{operands: [true]})
        ] do
      assert_raise ArgumentError, fn -> Code.eval_quoted(ast) end
    end

    assert {expression, []} =
             Code.eval_quoted(quote(do: %Jido.Expr.Operation{operator: :not, operands: [true]}))

    assert expression == Expr.new!(:not, [true])
  end

  @tag obligation: "jido_action.expression.I2"
  test "macro pins accept variables but reject calls before application work" do
    variable = Macro.var(:value, nil)

    pinned =
      quote do
        require Jido.Expr
        Jido.Expr.expr(^unquote(variable) + 1)
      end

    assert {expression, [value: 4]} = Code.eval_quoted(pinned, value: 4)
    assert expression == Expr.new!(:+, [4, 1])

    tag = System.unique_integer([:positive])

    ast =
      quote do
        require Jido.Expr
        Jido.Expr.expr(^send(self(), unquote(tag)) + 1)
      end

    assert_raise Expr.Error, fn -> Code.eval_quoted(ast) end
    refute_received ^tag
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I3"]
  test "errors retain safe operator types and useful exception messages" do
    for operator <- [:private_operator, "private", %{secret: "private"}] do
      expected = if is_atom(operator), do: operator

      assert {:error, %Expr.Error{operator: ^expected, reason: :unknown_operator}} =
               Expr.new(operator, [])
    end

    for {value, type} <- [
          {nil, nil},
          {false, :boolean},
          {42, :integer},
          {1.5, :float},
          {"private", :binary},
          {:private, :atom},
          {[], :list},
          {%{}, :map}
        ] do
      operator = if is_boolean(value), do: :+, else: :not
      operands = if operator == :+, do: [value, 1], else: [value]
      reason = if operator == :+, do: :invalid_numeric_operands, else: :invalid_boolean_operand
      types = if operator == :+, do: [type, :integer], else: [type]

      assert {:error,
              %Expr.Error{
                reason: ^reason,
                operator: ^operator,
                path: [],
                details: %{types: ^types}
              } = error} =
               Expr.evaluate(Expr.new!(operator, operands))

      message = Exception.message(error)
      assert message =~ "invalid expression: #{reason}"
      assert message =~ "(#{operator})"
      assert message =~ "at []"
      refute message =~ "private"
    end

    for {value, type} <- [
          {{:private, 1}, :tuple},
          {self(), :other},
          {make_ref(), :other},
          {fn -> :private end, :other}
        ] do
      assert {:error,
              %Expr.Error{
                reason: :unsupported_value,
                path: [:operands, 0],
                details: %{type: ^type}
              }} =
               Expr.evaluate(Expr.new!(:not, [value]))
    end

    error = %Expr.Error{reason: :unsupported_value, path: [:operands, 1, "field"]}

    assert Exception.message(error) ==
             "invalid expression: unsupported_value at [:operands, 1, \"field\"]"
  end

  @tag obligation: "jido_action.expression.I2"
  test "the parser retains wrappers, canonical nodes and literal map data" do
    expression = Expr.new!(:==, [%{1 => [1, 2], "key" => nil}, %{}])
    assert Expr.parse(expression) == {:ok, expression}

    assert Expr.parse({:expr, [], [Macro.escape(expression)]},
             leaf_parser: fn _ -> {:ok, expression} end
           ) == {:ok, expression}

    ast = {:==, [], [%{1 => [1, 2], "key" => nil}, %{}]}
    assert Expr.parse(ast) == {:ok, expression}
    assert Expr.parse(quote(do: expr(1 + 2))) == {:ok, Expr.new!(:+, [1, 2])}

    for ast <- [quote(do: expr()), quote(do: expr(1, 2))] do
      assert {:error, %Expr.Error{reason: :invalid_arity}} =
               Expr.parse(ast,
                 leaf_parser: fn _ -> flunk("reserved syntax must not reach the host") end
               )
    end

    assert {:error, %Expr.Error{reason: :unsupported_syntax, path: [:operands, 1]}} =
             Expr.parse(quote(do: 1 + ^value))

    reference = %Reference{}

    assert {:ok, %Jido.Expr.Operation{operands: [^reference]}} =
             Expr.parse(Expr.new!(:not, [reference]),
               leaf_parser: fn ^reference -> {:ok, reference} end
             )
  end

  @tag obligation: ["jido_action.expression.I2", "jido_action.expression.I3"]
  test "parser failures identify nested list, operand and map locations" do
    for {ast, reason, path} <- [
          {quote(do: 1 == [0, unknown()]), :unsupported_syntax, [:operands, 1, 1]},
          {{:==, [], [[1 | 2], []]}, :improper_list, [:operands, 0, 1]},
          {quote(do: 1 == %{a: unknown()}), :unsupported_syntax, [:operands, 1, :a]},
          {quote(do: 1 == %{a: 1, a: 2}), :duplicate_key, [:operands, 1, :a]},
          {{:==, [], [{:%{}, [], [invalid: 1, invalid: 2]}, nil]}, :duplicate_key, [:operands, 0, :invalid]},
          {{:==, [], [{:%{}, [], [nil]}, nil]}, :invalid_map_key, [:operands, 0]},
          {{:==, [], [%{1.5 => 1}, nil]}, :invalid_map_key, [:operands, 0]},
          {{:==, [], [%Jido.Expr.Operation{operator: :unknown, operands: []}, nil]}, :unknown_operator, [:operands, 0]}
        ] do
      assert {:error, %Expr.Error{reason: ^reason, path: ^path}} = Expr.parse(ast)
    end

    location = [:operands, 1, :a, 0]
    ast = quote(do: 1 == %{a: [field()]})
    host_error = %Expr.Error{reason: :host_rejected, path: [:child]}

    for {result, expected} <- [
          {:error, %Expr.Error{reason: :unsupported_syntax, path: location}},
          {:invalid, %Expr.Error{reason: :invalid_callback_return, path: location}},
          {{:error, host_error}, %{host_error | path: location ++ [:child]}},
          {{:error, :host_error}, :host_error}
        ] do
      assert {:error, ^expected} = Expr.parse(ast, leaf_parser: fn _ -> result end)
    end
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "parser depths and map key budgets report the first failing location" do
    for {ast, options, path} <- [
          {quote(do: 1 == [2]), [max_depth: 1], [:operands, 1, 0]},
          {quote(do: 1 == %{a: 2}), [max_depth: 1], [:operands, 1, :a]},
          {quote(do: 1 == %{a: [2]}), [max_depth: 2], [:operands, 1, :a, 0]}
        ] do
      assert {:error, %Expr.Error{reason: :max_depth, path: ^path}} = Expr.parse(ast, options)

      assert {:ok, %Jido.Expr.Operation{}} =
               Expr.parse(ast, max_depth: options[:max_depth] + 1)
    end

    for key <- ["private", 16, -16] do
      {options, reason} =
        if is_binary(key),
          do: {[max_binary_bytes: 6], :max_binary_bytes},
          else: {[max_integer_bits: 4], :max_integer_bits}

      ast = {:==, [], [{:%{}, [], [{key, 0}]}, nil]}

      assert {:error, %Expr.Error{reason: ^reason, path: [:operands, 0, ^key]}} =
               Expr.parse(ast, options)
    end

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 0, "private"]}} =
             Expr.parse(quote(do: %{"private" => nil} == nil),
               max_depth: 1,
               max_binary_bytes: 1
             )
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "all public walkers validate options and the documented maximum option values" do
    expression = Expr.new!(:not, [true])

    calls = [
      &Expr.parse(quote(do: not true), &1),
      &Expr.validate(expression, &1),
      &Expr.evaluate(expression, &1),
      &Expr.normalize(expression, &1),
      &Expr.reduce(expression, 0, fn _, n -> {:cont, n + 1} end, &1)
    ]

    for call <- calls do
      for options <- [
            nil,
            %{},
            [unknown: true],
            [max_depth: 1.0],
            [max_nodes: 0],
            [max_binary_bytes: 1_048_576_001],
            [max_integer_bits: 1_048_577]
          ] do
        assert {:error, %Expr.Error{reason: :invalid_options}} = call.(options)
      end

      for {key, maximum} <- [
            max_depth: 1_048_576_000,
            max_nodes: 1_048_576_000,
            max_binary_bytes: 1_048_576_000,
            max_integer_bits: 1_048_576
          ] do
        result = call.([{key, maximum}])
        assert result == :ok or match?({:ok, _}, result)
        assert {:error, %Expr.Error{reason: :invalid_options}} = call.([{key, maximum + 1}])
      end
    end

    for {call, option, arities} <- [
          {&Expr.parse(quote(do: not true), &1), :leaf_parser, [0, 2, 3]},
          {&Expr.evaluate(expression, &1), :resolve, [0, 3]},
          {&Expr.validate(expression, &1), :validate_leaf, [0, 3]},
          {&Expr.normalize(expression, &1), :normalize_leaf, [0, 3]}
        ],
        arity <- arities do
      callback =
        case arity do
          0 -> fn -> :ok end
          2 -> fn _, _ -> :ok end
          3 -> fn _, _, _ -> :ok end
        end

      assert {:error, %Expr.Error{reason: :invalid_options}} = call.([{option, callback}])
    end
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I3"]
  test "Boolean error and resolver paths retain the exact operand index" do
    reference = %Reference{}

    for {operator, left} <- [and: true, or: false] do
      expression = Expr.new!(operator, [left, %{nested: [reference]}])
      path = [:operands, 1, :nested, 0]
      error = %Expr.Error{reason: :host_error, path: [:child]}

      assert {:error, %{error | path: path ++ [:child]}} ==
               Expr.evaluate(expression,
                 resolve: fn ^reference, actual ->
                   assert actual == path
                   {:error, error}
                 end
               )
    end

    for operator <- [:and, :or] do
      assert {:error,
              %Expr.Error{
                reason: :invalid_boolean_operand,
                operator: ^operator,
                path: [:operands, 0],
                details: %{types: [:integer]}
              }} =
               Expr.evaluate(Expr.new!(operator, [123, true]))

      expression = Expr.new!(operator, [Expr.new!(:not, [false]), false])
      expected = operator == :or
      assert Expr.evaluate(expression, max_depth: 2) == {:ok, expected}

      assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 0, :operands, 0]}} =
               Expr.evaluate(expression, max_depth: 1)
    end
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I3"]
  test "unary numeric and membership type failures retain operand types" do
    for operator <- [:-, :abs] do
      assert {:error,
              %Expr.Error{
                reason: :invalid_numeric_operands,
                operator: ^operator,
                details: %{types: [:atom]}
              }} =
               Expr.evaluate(Expr.new!(operator, [:private]))
    end

    for {value, type} <- [
          {nil, nil},
          {false, :boolean},
          {1, :integer},
          {1.5, :float},
          {:private, :atom},
          {"private", :binary},
          {%{}, :map}
        ] do
      assert {:error,
              %Expr.Error{
                reason: :invalid_membership_right_operand,
                operator: :in,
                details: %{types: [^type]}
              }} =
               Expr.evaluate(Expr.new!(:in, [0, value]))
    end
  end

  @tag obligation: "jido_action.expression.I4"
  test "membership cost reuse neither overcharges nor hides the first failing binary" do
    expression = Expr.new!(:in, [%{items: ["x"]}, List.duplicate(%{items: ["y"]}, 8)])

    for limits <- [[max_nodes: 103], [max_nodes: 126], [max_binary_bytes: 30]] do
      assert {:ok, false} = Expr.evaluate(expression, limits)
    end

    assert {:error, %Expr.Error{reason: :max_nodes, operator: :in, path: []}} =
             Expr.evaluate(expression, max_nodes: 102)

    expression =
      Expr.new!(:in, [%{items: ["abc", 1]}, [%{items: ["xyz", 1]}, %{items: ["abc", 1.0]}]])

    assert {:error, %Expr.Error{reason: :max_binary_bytes, path: [0]}} =
             Expr.evaluate(expression, max_binary_bytes: 17)
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "reduction preserves ordered traversal, early errors and every callback failure kind" do
    value = %{outer: [1, 2]}

    assert {:ok, [[], [:outer], [:outer, 0], [:outer, 1]]} =
             Expr.reduce(value, [], fn _, path, acc -> {:cont, acc ++ [path]} end)

    assert {:ok, 4} = Expr.reduce(value, 0, fn _, acc -> {:cont, acc + 1} end)

    for callback <- [
          fn _, _ -> raise "private" end,
          fn _, _ -> throw(:private) end,
          fn _, _ -> exit(:private) end
        ] do
      assert {:error, %Expr.Error{reason: :reducer_failure, path: [:outer, 0]}} =
               Expr.reduce(value, nil, fn
                 1, _, acc -> callback.(1, acc)
                 _, _, acc -> {:cont, acc}
               end)
    end

    host_error = %Expr.Error{reason: :host_error, path: [:relative]}

    assert Expr.reduce([1, 2], nil, fn
             1, _ -> {:error, host_error}
             _, acc -> {:cont, acc}
           end) == {:error, host_error}

    assert {:ok, :halted} = Expr.reduce([1, 2], nil, fn _, _ -> {:halt, :halted} end)

    assert {:error, %Expr.Error{reason: :max_depth, path: [:outer, 0]}} =
             Expr.reduce(value, nil, fn _, acc -> {:cont, acc} end, max_depth: 1)

    assert {:ok, nil} = Expr.reduce(value, nil, fn _, acc -> {:cont, acc} end, max_depth: 2)
  end

  @tag obligation: "jido_action.expression.I3"
  test "normalizer and validator errors preserve host errors and reject invalid returns" do
    reference = %Reference{}
    value = %{outer: [reference]}
    path = [:outer, 0]
    error = %Expr.Error{reason: :host_error, path: [:child]}

    for {result, expected} <- [
          {{:error, error}, %{error | path: path ++ [:child]}},
          {{:error, :host_error}, :host_error},
          {:bad, %Expr.Error{reason: :invalid_callback_return, path: path}}
        ],
        option <- [:normalize_leaf, :validate_leaf] do
      assert Expr.normalize(value, [
               {option,
                fn ^reference, actual ->
                  assert actual == path
                  result
                end}
             ]) == {:error, expected}
    end

    for callback <- [
          fn _ -> raise "private" end,
          fn _ -> throw(:private) end,
          fn _ -> exit(:private) end
        ] do
      assert {:error, %Expr.Error{reason: :callback_failure, path: ^path}} =
               Expr.normalize(value, normalize_leaf: callback)
    end

    assert {:error, %Expr.Error{reason: :unsupported_value, path: ^path, details: %{type: :struct}}} =
             Expr.normalize(value)

    assert {:error,
            %Expr.Error{
              reason: :unsupported_value,
              path: [:operands, 0],
              details: %{type: :struct}
            }} =
             Expr.evaluate(Expr.new!(:not, [reference]))
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "map keys and values have bounded depths through every runtime walk" do
    data = %{outer: [1]}
    expression = Expr.new!(:==, [data, nil])

    for call <- [
          &Expr.normalize(data, &1),
          &Expr.reduce(data, nil, fn _, acc -> {:cont, acc} end, &1)
        ] do
      assert {:error, %Expr.Error{reason: :max_depth, path: [:outer, 0]}} =
               call.(max_depth: 1)

      assert match?({:ok, _}, call.(max_depth: 2))
    end

    assert :ok = Expr.validate(expression, max_depth: 3)

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 0, :outer, 0]}} =
             Expr.validate(expression, max_depth: 2)

    assert {:error, %Expr.Error{reason: :max_depth, path: [:outer, "private"]}} =
             Expr.normalize(%{outer: %{"private" => nil}}, max_depth: 1, max_binary_bytes: 1)

    reference = %Reference{}

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 1]}} =
             Expr.evaluate(Expr.new!(:and, [true, reference]),
               resolve: fn _ -> {:ok, %{"private" => nil}} end,
               max_depth: 1,
               max_binary_bytes: 1
             )

    for key <- [1.5, {1, 2}] do
      type = if is_float(key), do: :float, else: :tuple

      for call <- [&Expr.normalize/1, fn data -> Expr.validate(Expr.new!(:==, [data, nil])) end] do
        assert {:error, %Expr.Error{reason: :invalid_map_key, details: %{type: ^type}}} =
                 call.(%{key => nil})
      end
    end
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I4"]
  test "resolved tuples and improper lists stay inert but have checked children" do
    reference = %Reference{}
    value = {1, [2 | 3]}
    expression = Expr.new!(:and, [true, reference])
    resolve = fn ^reference -> {:ok, value} end
    assert Expr.evaluate(expression, resolve: resolve, max_depth: 3) == {:ok, value}

    for data <- [[1, 2], [1 | 2], %{items: [1, 2]}] do
      assert Expr.evaluate(expression, resolve: fn ^reference -> {:ok, data} end) == {:ok, data}
    end

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 1, 1, 0]}} =
             Expr.evaluate(expression, resolve: resolve, max_depth: 2)

    for {replacement, options, path} <- [
          {{16, 0}, [max_integer_bits: 4], [:operands, 1, 0]},
          {{0, -16}, [max_integer_bits: 4], [:operands, 1, 1]},
          {[0 | 16], [max_integer_bits: 4], [:operands, 1, 1]}
        ] do
      assert {:error, %Expr.Error{reason: :max_integer_bits, path: ^path}} =
               Expr.evaluate(expression, [resolve: fn _ -> {:ok, replacement} end] ++ options)
    end

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 1, 1, 0]}} =
             Expr.evaluate(expression,
               resolve: fn _ -> {:ok, [0 | {1}]} end,
               max_depth: 2
             )
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "resolved map failures omit private keys and retain list indexes" do
    reference = %Reference{}
    expression = Expr.new!(:and, [true, reference])

    for key <- [:field, "field", 0] do
      assert {:ok, %{^key => nil}} =
               Expr.evaluate(expression, resolve: fn _ -> {:ok, %{key => nil}} end, max_depth: 2)

      assert {:error, %Expr.Error{reason: :max_integer_bits, path: [:operands, 1, 0]}} =
               Expr.evaluate(expression,
                 resolve: fn _ -> {:ok, %{key => [16]}} end,
                 max_integer_bits: 4
               )
    end

    assert {:ok, %{items: [0]}} =
             Expr.evaluate(expression, resolve: fn _ -> {:ok, %{items: [0]}} end, max_depth: 3)

    assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 1, 0]}} =
             Expr.evaluate(expression, resolve: fn _ -> {:ok, %{items: [0]}} end, max_depth: 2)

    key = {:opaque, "private"}

    assert {:error, %Expr.Error{reason: :max_integer_bits, path: [:operands, 1]}} =
             Expr.evaluate(expression,
               resolve: fn _ -> {:ok, %{key => 16}} end,
               max_integer_bits: 4
             )
  end

  @tag obligation: "jido_action.expression.I4"
  test "Boolean resolution respects depth and concatenation admits its exact byte boundary" do
    reference = %Reference{}

    for {operator, left} <- [and: true, or: false] do
      expression = Expr.new!(operator, [left, reference])
      assert {:ok, [0]} = Expr.evaluate(expression, resolve: fn _ -> {:ok, [0]} end, max_depth: 2)

      assert {:error, %Expr.Error{reason: :max_depth, path: [:operands, 1, 0]}} =
               Expr.evaluate(expression, resolve: fn _ -> {:ok, [0]} end, max_depth: 1)
    end

    assert {:ok, "abcdef"} = Expr.evaluate(Expr.new!(:<>, ["abc", "def"]), max_binary_bytes: 12)

    assert {:error, %Expr.Error{reason: :max_binary_bytes, operator: :<>, path: []}} =
             Expr.evaluate(Expr.new!(:<>, ["abc", "def"]), max_binary_bytes: 11)
  end

  @tag obligation: ["jido_action.expression.I2", "jido_action.expression.I4"]
  test "scalar roots stay data and do not become standalone expressions" do
    for value <- [nil, true, 0, "value", [], %{}] do
      assert {:error, %Expr.Error{reason: :expected_expression, path: []}} = Expr.evaluate(value)
      assert {:error, %Expr.Error{reason: :expected_expression, path: []}} = Expr.validate(value)
      assert {:ok, ^value} = Expr.normalize(value)
    end
  end
end
