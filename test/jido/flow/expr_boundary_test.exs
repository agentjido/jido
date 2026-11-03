defmodule JidoActionTest.Flow.ExprBoundaryTest do
  use ExUnit.Case, async: true
  alias Jido.Expr
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.DSL.ValueParser
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  test "encoding rejects expression documents that exceed the reader's depth limit" do
    for count <- [1, 20] do
      flow = output_flow(%{value: nested_negate(count)})
      assert {:ok, document, registry} = Codec.encode(flow)
      assert {:ok, ^flow} = Codec.decode(document, registry)
    end

    flow = output_flow(%{value: nested_negate(40)})
    result = Codec.encode(flow)
    assert elem(result, 0) == :error
    {:error, error} = result
    assert error.message == "stored Flow exceeds its nesting limit"
    assert error.details.maximum_depth == 100
  end

  test "calculated conditions keep one budget across fields and authoring forms" do
    calculation = Expr.new!(:<>, [Ref.input(:data), ""])
    expression = Expr.new!(:==, [calculation, Ref.input(:data)])

    assert {:ok, parsed} =
             ValueParser.parse_condition(
               quote do
                 input(:data) <> "" == input(:data)
               end
             )

    for condition <- [expression, parsed, Jido.Expr.new!(:==, [calculation, Ref.input(:data)])] do
      assert {:ok, ^expression} = Jido.Flow.Value.condition(condition, :any)
      choice = choice_flow(condition)
      assert {:ok, document, registry} = Codec.encode(choice)
      assert {:ok, ^choice} = Codec.decode(document, registry)
      assert Jido.Exec.run(choice, %{data: "short"}) == {:ok, %{selected: true}}

      for flow <- [output_flow(%{selected: condition}), choice, iterator_flow(condition)] do
        assert {:error, error} = Jido.Exec.run(flow, %{data: String.duplicate("x", 300_000)})
        assert error.details.reason == :max_binary_bytes
        assert error.details.retry == false
      end
    end
  end

  test "Boolean operations keep the full calculated condition in the shared evaluator" do
    calculation = Expr.new!(:<>, [Ref.input(:data), ""])
    comparison = Expr.new!(:==, [calculation, Ref.input(:data)])
    comparison_true = Jido.Expr.new!(:==, [1, 1])

    for condition <- [
          Expr.new!(:and, [comparison_true, Expr.new!(:==, [calculation, Ref.input(:data)])]),
          Expr.new!(:or, [Expr.new!(:==, [calculation, Ref.input(:data)]), comparison_true]),
          Expr.new!(:not, [Expr.new!(:==, [calculation, Ref.input(:data)])]),
          Expr.new!(:and, [Expr.new!(:==, [1, 1]), comparison])
        ] do
      assert {:ok, %Jido.Expr.Operation{}} = Jido.Flow.Value.condition(condition, :any)

      assert {:error, error} =
               Jido.Exec.run(choice_flow(condition), %{data: String.duplicate("x", 300_000)})

      assert error.details.reason == :max_binary_bytes
    end
  end

  test "plain data keeps its DSL, direct and version-two storage contracts" do
    cases = [
      %{items: List.duplicate(1, 10_000)},
      %{text: String.duplicate("x", 1_048_577)},
      %{number: Bitwise.bsl(1, 4096)},
      %{nested: Enum.reduce(1..70, 1, fn _, value -> [value] end)}
    ]

    for {value, index} <- Enum.with_index(cases) do
      source = Macro.escape(value)
      assert {:ok, ^value} = ValueParser.parse(source)
      direct = output_flow(value)

      assert {:ok, built} =
               JidoActionTest.FlowBuilder.new(%{
                 output: value,
                 components: [%{kind: :step, name: "seed", action: EchoParamsAction, params: %{}}],
                 name: "expression_boundary"
               })

      assert built == direct
      assert module_flow(Module.concat(__MODULE__, "Plain#{index}"), source) == direct
      assert {:ok, document, registry} = Codec.encode(direct)
      assert document["vsn"] == 2
      assert {:ok, ^direct} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
      assert Jido.Exec.run(direct) == {:ok, value}
    end
  end

  test "plain in-memory data is not subject to expression depth limits" do
    value = %{nested: Enum.reduce(1..129, 1, fn _, data -> [data] end)}
    assert {:ok, ^value} = ValueParser.parse(Macro.escape(value))
    assert {:ok, ^value} = Jido.Flow.Value.normalize(value)
    assert output_flow(value).output == value
  end

  test "actual operations still reject oversized operands in every authoring form" do
    for value <- [
          String.duplicate("x", 1_048_577),
          Bitwise.bsl(1, 4096),
          List.duplicate(1, 10_000),
          Enum.reduce(1..70, 1, fn _, data -> [data] end)
        ] do
      expression = Expr.new!(:==, [value, value])

      assert {:error, _} =
               ValueParser.parse(
                 quote do
                   unquote(value) == unquote(value)
                 end
               )

      assert {:error, _} =
               JidoActionTest.FlowComponent.step(
                 name: "seed",
                 action: EchoParamsAction,
                 params: %{v: expression}
               )
    end
  end

  test "normalization counts the complete operation tree" do
    conditions = List.duplicate(Expr.new!(:==, [1, 1]), 4000)
    expression = balanced_and(conditions)

    assert {:error, error} =
             Jido.Flow.Value.condition(expression, :any)

    assert error.details.reason == :max_nodes
    assert {:error, error} = Jido.Flow.Value.normalize(expression)
    assert error.details.reason == :max_nodes
  end

  test "plain-data parsing keeps malformed data and executable calls out of Flow values" do
    for value <- [
          [1 | 2],
          {:%{}, [], [{:value, 1} | 2]},
          {:%{}, [], [:invalid_pair]},
          quote do
            %{1.5 => 1}
          end,
          quote do
            %{nested: [Date.utc_today()]}
          end,
          quote do
            %{duplicate: 1, duplicate: 2}
          end
        ] do
      assert {:error, %Jido.Error.ValidationError{}} = ValueParser.parse(value)
    end
  end

  test "nested validation errors contain each container location once" do
    expression = Expr.new!(:+, [Ref.item(), 1])

    assert {:error, error} =
             JidoActionTest.FlowComponent.step(
               name: "seed",
               action: EchoParamsAction,
               params: %{outer: [%{inner: expression}]}
             )

    assert error.details.path == [:call, :params, :outer, 0, :inner, :operands, 0]
    condition = Expr.new!(:==, [Ref.item(), 1])
    assert {:error, error} = Jido.Flow.Value.validate(%{outer: [condition]}, :flow)
    assert error.details.path == [:outer, 0, :operands, 0]
    assert {:error, error} = Jido.Flow.Value.validate(%{outer: %{1.5 => :invalid}}, :flow)
    assert error.details.path == [:outer]
  end

  test "missing references in a calculated Choice retain the full error location" do
    expression = Expr.new!(:==, [Expr.new!(:+, [Ref.input(:missing), 1]), 2])
    assert {:error, error} = Jido.Exec.run(choice_flow(expression))
    assert error.phase == :choice_condition
    assert error.details.node == "route"
    assert error.details.option == "yes"
    assert error.details.path == [:missing]
    assert error.details.expression_path == [:operands, 0, :operands, 0]
    assert error.details.retry == false
  end

  test "invalid stored operation names retain Choice and Iterate JSON locations" do
    expression = Expr.new!(:==, [Expr.new!(:+, [1, 1]), 2])
    invalid = %{"$expr" => %{"operator" => "unknown", "operands" => []}}

    for {flow, path, expected_path} <- [
          {choice_flow(expression), ["components", Access.at(0), "options", Access.at(0), "condition"],
           ["components", 0, "options", 0, "condition", "$expr", "operator"]},
          {iterator_flow(expression), ["components", Access.at(0), "completion"],
           ["components", 0, "completion", "$expr", "operator"]}
        ] do
      assert {:ok, document, registry} = Codec.encode(flow)
      assert {:error, error} = Codec.decode(put_in(document, path, invalid), registry)

      assert error.details.path == expected_path
    end
  end

  test "canonical operations preserve Flow string and map-key rules" do
    for data <- [<<255>>, %{nil: 1}, %{-1 => 1}, %{<<255>> => 1}] do
      expression = Expr.new!(:==, [data, data])
      assert :ok = Expr.validate(expression)

      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.Flow.Value.validate(expression)

      assert {:error, %Jido.Error.ValidationError{}} =
               JidoActionTest.FlowComponent.step(
                 name: "seed",
                 action: EchoParamsAction,
                 params: %{nested: expression}
               )

      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.Flow.Value.condition(
                 %Jido.Expr.Operation{operator: :==, operands: [data, data]},
                 :any
               )
    end
  end

  test "skipped nested operations still validate Flow data and reference scopes" do
    for data <- [Ref.item(), <<255>>, %{nil: 1}, %{-1 => 1}] do
      expression = Expr.new!(:and, [false, Expr.new!(:==, [data, 1])])

      assert {:error, %Jido.Error.ValidationError{} = error} =
               Jido.Flow.Value.condition(expression, :flow)

      assert error.details.path == [:operands, 1, :operands, 0]
    end
  end

  test "invalid result names retain their complete normalization path" do
    reference = Ref.result("")
    expression = Expr.new!(:==, [Expr.new!(:==, [reference, 1]), true])
    assert {:error, error} = Jido.Flow.Value.condition(expression, :any)
    assert Exception.message(error) == "Action name cannot be blank."
    assert error.details.path == [:operands, 0, :operands, 0]

    assert {:error, error} =
             JidoActionTest.FlowComponent.step(
               name: "seed",
               action: EchoParamsAction,
               params: %{outer: [expression]}
             )

    assert error.details.path == [:call, :params, :outer, 0, :operands, 0, :operands, 0]
    assert {:error, error} = Jido.Flow.Value.normalize(%{outer: [reference]})
    assert error.details.path == [:outer, 0]
  end

  test "stored arity errors retain their expression tag paths" do
    assert {:ok, document, registry} = Codec.encode(choice_flow(Expr.new!(:==, [1, 1])))
    location = ["components", Access.at(0), "options", Access.at(0), "condition"]

    for {operator, operands} <- [{"==", [1]}, {"not", []}, {"and", []}] do
      tag = "$expr"

      invalid = %{
        tag => %{
          "operator" => "not",
          "operands" => [%{tag => %{"operator" => operator, "operands" => operands}}]
        }
      }

      invalid_document = put_in(document, location, invalid)

      assert {:error, error} =
               Codec.decode(JSON.decode!(JSON.encode!(invalid_document)), registry)

      assert error.details.reason == :invalid_arity

      assert error.details.path == [
               "components",
               0,
               "options",
               0,
               "condition",
               tag,
               "operands",
               0,
               tag
             ]
    end
  end

  defp nested_negate(count) do
    Enum.reduce(1..count, 1, fn _, value -> Expr.new!(:-, [value]) end)
  end

  defp balanced_and([expression]), do: expression

  defp balanced_and(expressions) do
    expressions
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [left, right] -> Expr.new!(:and, [left, right])
      [expression] -> expression
    end)
    |> balanced_and()
  end

  defp output_flow(value) do
    JidoActionTest.FlowBuilder.new!(
      name: "expression_boundary",
      components: [JidoActionTest.FlowComponent.step!(name: "seed", action: EchoParamsAction)],
      output: value
    )
  end

  defp choice_flow(condition) do
    choice =
      JidoActionTest.FlowComponent.choice!(
        name: "route",
        options: [
          %{
            name: "yes",
            condition: condition,
            action: EchoParamsAction,
            params: %{selected: true}
          }
        ],
        fallback: [action: EchoParamsAction, params: %{selected: false}]
      )

    JidoActionTest.FlowBuilder.new!(
      name: "expression_boundary",
      components: [choice],
      output: Ref.result("route")
    )
  end

  defp iterator_flow(condition) do
    iterator =
      JidoActionTest.FlowComponent.iterate!(
        name: "loop",
        action: EchoParamsAction,
        state: [schema: Jido.Joi.map(), initial: %{}, update: %{}],
        completion: condition,
        max_iterations: 1
      )

    JidoActionTest.FlowBuilder.new!(
      name: "expression_boundary",
      components: [iterator],
      output: Ref.result("loop")
    )
  end

  defp module_flow(module, source) do
    body =
      quote do
        use Jido.Flow, name: "expression_boundary"

        flow do
          step("seed", action: unquote(EchoParamsAction), params: %{})
          output(unquote(source))
        end
      end

    Module.create(module, body, Macro.Env.location(__ENV__))
    module.flow()
  end
end
