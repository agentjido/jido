defmodule JidoActionTest.Flow.DSL.ExpressionTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Ref
  alias Jido.Flow.DSL.ValueParser

  test "lowers the closed Flow expression vocabulary" do
    expression =
      quote do
        %{
          input: input(),
          input_path: input(:id),
          context: context(),
          context_path: context([:request, :id]),
          result: result("loaded"),
          result_path: result("loaded", :id),
          selected: select(result("loaded"), [:customer, :id]),
          item: item(),
          item_path: item(:price),
          item_index: item_index(),
          item_id: item_id(),
          accumulator: accumulator(),
          accumulator_path: accumulator(:total),
          state: state(),
          state_path: state(:status),
          iteration_index: iteration_index(),
          body_result: body_result(),
          body_result_path: body_result(:status),
          literal: value(:ok),
          nested: [1, true, nil, "value"]
        }
      end

    assert {:ok, parsed} = ValueParser.parse(expression)
    assert parsed.input == Ref.input([])
    assert parsed.input_path == Ref.input(:id)
    assert parsed.context == Ref.context([])
    assert parsed.context_path == Ref.context([:request, :id])
    assert parsed.result == Ref.result("loaded")
    assert parsed.result_path == Ref.result("loaded", :id)
    assert parsed.selected == Ref.result("loaded", [:customer, :id])
    assert parsed.item == Ref.item()
    assert parsed.item_path == Ref.item(:price)
    assert parsed.item_index == Ref.item_index()
    assert parsed.item_id == Ref.item_id()
    assert parsed.accumulator == Ref.accumulator()
    assert parsed.accumulator_path == Ref.accumulator(:total)
    assert parsed.state == Ref.state()
    assert parsed.state_path == Ref.state(:status)
    assert parsed.iteration_index == Ref.iteration_index()
    assert parsed.body_result == Ref.body_result()
    assert parsed.body_result_path == Ref.body_result(:status)
    assert parsed.literal == :ok
    assert parsed.nested == [1, true, nil, "value"]
  end

  test "lowers native condition forms and rejects non-Elixir aliases" do
    native =
      quote do
        input(:kind) in [:priority, :express] and
          not (context(:blocked) == true or input(:total) < 0)
      end

    assert {:ok, %Jido.Expr{operator: :and}} = ValueParser.parse_condition(native)

    for expression <- [
          quote(do: eq(input(:kind), :priority)),
          quote(do: gte(input(:total), 10)),
          quote(do: all([true, false])),
          quote(do: any([false, true]))
        ] do
      assert {:error, _error} = ValueParser.parse_condition(expression)
    end
  end

  test "lowers empty list literals without changing reference paths or keyword rejection" do
    assert {:ok, []} = ValueParser.parse(quote(do: []))
    assert {:ok, []} = ValueParser.parse(quote(do: value([])))

    assert {:ok, %{items: [[], %{values: []}]}} =
             ValueParser.parse(quote(do: %{items: [[], %{values: []}]}))

    assert {:ok, %{items: []}} = ValueParser.parse(%{items: []})
    assert {:ok, ref} = ValueParser.parse(quote(do: input([])))
    assert ref == Ref.input([])
    assert {:ok, ref} = ValueParser.parse(quote(do: result("step", [])))
    assert ref == Ref.result("step")
    assert {:error, _error} = ValueParser.parse(quote(do: [items: []]))
  end

  test "lowers empty lists in comparison operands" do
    assert {:ok, %Jido.Expr{operator: :==, operands: [ref, []]}} =
             ValueParser.parse_condition(quote(do: input(:items) == []))

    assert ref == Ref.input(:items)

    assert {:ok, %Jido.Expr{operator: :in, operands: [1, []]}} =
             ValueParser.parse_condition(quote(do: 1 in []))
  end

  test "explicit literals retain negative numbers without widening paths or map keys" do
    assert {:ok, -1} = ValueParser.parse(quote(do: value(-1)))

    assert {:ok, %{amounts: [-2, %{amount: -3.5}]}} =
             ValueParser.parse(quote(do: value(%{amounts: [-2, %{amount: -3.5}]})))

    # A negative number is literal data, as in a data definition.
    assert {:ok, -1} = ValueParser.parse(quote(do: -1))
    assert {:ok, %Jido.Expr{operator: :-}} = ValueParser.parse(quote(do: -input(:amount)))

    for expression <- [
          quote(do: value(-input(:amount))),
          quote(do: value(1 - 2)),
          quote(do: value(%{-1 => :value})),
          Code.string_to_quoted!("value(%{-1 => :first,\n-1 => :second})")
        ] do
      assert {:error, _error} = ValueParser.parse(expression)
    end

    for expression <- [quote(do: input([-1])), quote(do: input([[-1]]))] do
      assert {:error, error} = ValueParser.parse(expression)
      assert error.message =~ "unsupported Flow expression"
    end
  end

  test "rejects executable expressions, keyword data, and invalid conditions" do
    assert {:error, error} = ValueParser.parse(quote(do: Date.utc_today()))

    assert Exception.message(error) ==
             "unsupported Flow expression: Date.utc_today(); use a Flow reference, literal, map, or list"

    assert {:error, error} = ValueParser.parse(status: :ready)
    assert Exception.message(error) =~ "unsupported Flow expression"

    assert {:error, error} = ValueParser.parse_condition(quote(do: :ready))

    assert Exception.message(error) ==
             "unsupported Flow condition: :ready; use a Boolean reference, Boolean literal, or Jido.Expr operation"
  end

  test "rejects assignment, pattern matching, and pipes as declarative data" do
    for expression <- [
          quote(do: selected = input(:value)),
          quote(do: %{value: selected} = input(:payload)),
          quote(do: input(:value) |> Integer.to_string())
        ] do
      assert {:error, error} = ValueParser.parse(expression)
      assert Exception.message(error) =~ "use a Flow reference, literal, map, or list"
    end
  end

  test "accepts canonical references and literal maps" do
    ref = Ref.result("loaded", :value)
    assert {:ok, ^ref} = ValueParser.parse(ref)

    assert {:ok, %{status: :ready}} = ValueParser.parse(quote(do: value(%{status: :ready})))

    assert {:ok, %{status: :ready}} = ValueParser.parse(%{status: :ready})
  end

  test "lowers every supported comparison" do
    for {expression, operator} <- [
          {quote(do: input(:left) == input(:right)), :==},
          {quote(do: input(:left) != input(:right)), :!=},
          {quote(do: input(:left) < input(:right)), :<},
          {quote(do: input(:left) <= input(:right)), :<=},
          {quote(do: input(:left) > input(:right)), :>},
          {quote(do: input(:left) >= input(:right)), :>=}
        ] do
      assert {:ok, %Jido.Expr{operator: ^operator}} = ValueParser.parse_condition(expression)
    end
  end

  test "rejects invalid result names, paths, selections, literals, and duplicate maps" do
    invalid = [
      quote(do: result(nil)),
      quote(do: input(1.5)),
      quote(do: select(%{value: 1}, :path)),
      quote(do: value(self())),
      quote(do: %{value: 1, value: 2})
    ]

    for expression <- invalid do
      assert {:error, error} = ValueParser.parse(expression)

      assert Enum.any?(
               ["unsupported Flow expression", "duplicate Flow map key"],
               &String.contains?(Exception.message(error), &1)
             )
    end
  end
end
