defmodule JidoActionTest.Flow.ExprTest do
  use Covenant.Case, component: "jido_action.expression", async: true
  alias Jido.Expr
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.DSL.ValueParser
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  @tag obligation: "jido_action.expression.I2"
  test "Flow parses transparent calculations and optional wrappers" do
    source =
      quote do
        %{total: input(:quantity) * input(:price), label: expr("Hi " <> input(:name))}
      end

    assert {:ok, value} = ValueParser.parse(source)
    assert value.total == Expr.new!(:*, [Ref.input(:quantity), Ref.input(:price)])
    assert value.label == Expr.new!(:<>, ["Hi ", Ref.input(:name)])

    assert {:ok, %{total: 6, label: "Hi Ada"}} =
             Jido.Exec.run(output_flow(value), %{quantity: 2, price: 3, name: "Ada"})
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I2"]
  test "direct, and stored calculations have the same model and result" do
    total = Expr.new!(:*, [Ref.result("load", :quantity), Ref.input(:price)])
    label = Expr.new!(:<>, [Ref.context(:prefix), Ref.input(:name)])

    step =
      JidoActionTest.FlowComponent.step!(
        name: "load",
        action: EchoParamsAction,
        params: %{quantity: Expr.new!(:+, [Ref.input(:quantity), 1])}
      )

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "calculated",
        components: [step],
        output: %{total: total, label: label}
      )

    assert {:ok, built} =
             JidoActionTest.FlowBuilder.new(%{
               output: direct.output,
               components: [
                 %{kind: :step, name: "load", action: EchoParamsAction, params: step.params}
               ],
               name: "calculated"
             })

    assert built == direct
    assert {:ok, document, registry} = Codec.encode(built)
    assert document["vsn"] == 2

    assert {:ok, restored} =
             document |> JSON.encode!() |> JSON.decode!() |> Codec.decode(registry)

    assert restored == direct
    assert Flow.semantic_identity(restored) == Flow.semantic_identity(direct)

    for flow <- [direct, built, restored] do
      assert Jido.Exec.run(flow, %{quantity: 2, price: 3, name: "Ada"}, %{prefix: "Hi "}) ==
               {:ok, %{total: 9, label: "Hi Ada"}}
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "Boolean references and literals are strict conditions and short circuit" do
    for {ast, input, expected} <- [
          {quote do
             input(:enabled)
           end, %{enabled: true}, true},
          {quote do
             not input(:enabled)
           end, %{enabled: false}, true},
          {quote do
             false and input(:missing)
           end, %{}, false},
          {quote do
             true or 1 / 0 > 0
           end, %{}, true}
        ] do
      assert {:ok, condition} = ValueParser.parse_condition(ast)
      assert Jido.Exec.run(choice_flow(condition), input) == {:ok, %{selected: expected}}
    end

    for value <- [nil, 0, "true", :ready] do
      assert {:error, error} = Jido.Exec.run(choice_flow(Ref.input(:enabled)), %{enabled: value})
      assert error.details.reason == :invalid_boolean_operand
    end

    assert Jido.Exec.run(choice_flow(true)) == {:ok, %{selected: true}}
    assert Jido.Exec.run(choice_flow(false)) == {:ok, %{selected: false}}

    assert Jido.Exec.run(choice_flow(Expr.new!(:not, [Ref.input(:enabled)])), %{enabled: false}) ==
             {:ok, %{selected: true}}
  end

  defmodule NativeOutput do
    use Jido.Flow, name: "native_boolean_output"

    flow do
      step("echo", action: EchoParamsAction, params: %{value: true and 123})
      output(%{value: result("echo", :value), fallback: false or "fallback"})
    end
  end

  @tag obligation: "jido_action.expression.I1"
  test "data fields accept native Boolean results but condition boundaries reject them" do
    assert Jido.Exec.run(NativeOutput) == {:ok, %{value: 123, fallback: "fallback"}}

    assert {:ok, condition} =
             ValueParser.parse_condition(
               quote do
                 true and 123
               end
             )

    assert {:error, error} = Jido.Exec.run(choice_flow(condition))
    assert error.details.reason == :invalid_boolean_operand
    assert error.phase == :choice_condition

    iterator =
      JidoActionTest.FlowComponent.iterate!(
        name: "loop",
        action: EchoParamsAction,
        state: [schema: Jido.Joi.map(), initial: %{}, update: %{}],
        completion: condition,
        max_iterations: 2
      )

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "native_condition",
        components: [iterator],
        output: Ref.result("loop")
      )

    assert {:error, error} = Jido.Exec.run(flow)
    assert error.details.reason == :invalid_boolean_operand
    assert error.phase == :iterate_completion
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I2"]
  test "nested result references remain dependencies even when skipped" do
    expression = Expr.new!(:or, [true, Expr.new!(:==, [Ref.result(:later, :value), 1])])

    first =
      JidoActionTest.FlowComponent.step!(
        name: "first",
        action: EchoParamsAction,
        params: %{selected: expression}
      )

    later =
      JidoActionTest.FlowComponent.step!(
        name: "later",
        action: EchoParamsAction,
        params: %{value: 1}
      )

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "nested_dependencies",
        components: [first, later],
        output: Ref.result("first")
      )

    assert Jido.Flow.Definition.reference_dependencies(flow.components["first"]) == ["later"]
    assert Jido.Exec.run(flow) == {:ok, %{selected: true}}

    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(
               name: "unknown_ref",
               components: [
                 JidoActionTest.FlowComponent.step!(name: "seed", action: EchoParamsAction)
               ],
               output: %{value: expression}
             )

    assert error.details.component == "later"

    assert {:error, _} =
             JidoActionTest.FlowComponent.step(
               name: "bad_scope",
               action: EchoParamsAction,
               params: %{value: Expr.new!(:+, [Ref.item(), 1])}
             )
  end

  @tag obligation: "jido_action.expression.I3"
  test "operation failures and missing references keep a useful location" do
    assert {:error, error} = Jido.Exec.run(output_flow(%{nested: [Expr.new!(:/, [1, 0])]}))
    assert error.details.operator == :/
    assert error.details.expression_path == [:nested, 0]
    assert error.details.retry == false
    expression = Expr.new!(:<>, ["Hi ", Ref.input(:missing)])

    assert {:error, error} =
             Jido.Exec.run(output_flow(%{label: expression}), %{secret: "do not expose"})

    assert error.details.path == [:missing]
    assert error.details.expression_path == [:label, :operands, 1]
    refute inspect(error.details) =~ "do not expose"

    assert Jido.Exec.run(output_flow(%{is_nil: Expr.new!(:==, [Ref.input(:value), nil])}), %{
             value: nil
           }) == {:ok, %{is_nil: true}}

    assert {:ok, %{value: 3}} = Jido.Exec.run(output_flow(%{value: Expr.new!(:+, [1, 2])}))
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "resolved private map keys are absent from complete Flow errors" do
    private_key = "private-token-as-key"
    private_value = String.duplicate("private-value", 100_000)
    expression = Expr.new!(:==, [Ref.context(:secrets), nil])

    assert {:error, error} =
             Jido.Exec.run(output_flow(%{answer: expression}), %{}, %{
               secrets: %{private_key => %{private_key => private_value}}
             })

    assert error.details.reason == :max_binary_bytes
    assert error.details.expression_path == [:answer, :operands, 0]
    assert error.details.retry == false
    refute inspect(error, limit: :infinity) =~ private_key
    refute inspect(error, limit: :infinity) =~ "private-value"
    refute inspect(Jido.Error.to_map(error), limit: :infinity) =~ private_key
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I3"]
  test "operations preserve all local reference scopes" do
    scopes = [
      :flow,
      :map_collection,
      :map_params,
      :reduce_collection,
      :reduce_initial,
      :reduce_params,
      :iterate_initial,
      :iterate_params,
      :iterate_update,
      :iterate_completion
    ]

    for reference <- [
          Ref.item(),
          Ref.item_index(),
          Ref.item_id(),
          Ref.accumulator(),
          Ref.state(),
          Ref.iteration_index(),
          Ref.body_result()
        ],
        scope <- scopes do
      expression = Expr.new!(:==, [reference, nil])

      case Ref.validate(reference, scope) do
        :ok ->
          assert :ok = Jido.Flow.Value.validate(expression, scope)

        {:error, _} ->
          assert {:error, error} = Jido.Flow.Value.validate(expression, scope)
          assert error.details.ref_type == reference.source
          assert error.details.scope == scope
      end
    end
  end

  @tag obligation: "jido_action.expression.I3"
  test "malformed references inside calculated conditions return validation errors" do
    reference = %Ref{source: :unknown, path: []}
    expression = Expr.new!(:+, [reference, 1])

    assert {:error, error} =
             Jido.Flow.Value.condition(
               %Jido.Expr.Operation{operator: :==, operands: [expression, 2]},
               :any
             )

    assert error.details.ref_type == :unknown
  end

  @tag obligation: "jido_action.expression.I3"
  test "iterator completion failures retain the expression and reference locations" do
    iterator =
      JidoActionTest.FlowComponent.iterate!(
        name: "loop",
        action: EchoParamsAction,
        state: [schema: Jido.Joi.map(), initial: %{}, update: %{}],
        completion: Expr.new!(:>, [Expr.new!(:+, [Ref.input(:missing), 1]), 0]),
        max_iterations: 2
      )

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "iterator_error",
        components: [iterator],
        output: Ref.result("loop")
      )

    assert {:error, error} = Jido.Exec.run(flow)
    assert error.phase == :iterate_completion
    assert error.details.path == [:missing]
    assert error.details.expression_path == [:operands, 0, :operands, 0]
    assert error.details.retry == false
  end

  @tag obligation: "jido_action.expression.I2"
  test "version two supports expressions and keeps literal maps distinct" do
    literal = %{"$expr" => %{"operator" => "+", "operands" => [1, 2]}}
    legacy = output_flow(literal)
    assert {:ok, document, registry} = Codec.encode(legacy)
    assert document["vsn"] == 2
    assert {:ok, restored} = Codec.decode(document, registry)
    assert Jido.Exec.run(restored) == {:ok, literal}
    expression = output_flow(%{value: Expr.new!(:+, [1, 2])})
    assert {:ok, expression_document, expression_registry} = Codec.encode(expression)

    assert Codec.decode(expression_document, expression_registry) == {:ok, expression}

    assert {:error, _} =
             Codec.decode(Map.put(expression_document, "vsn", 3), expression_registry)

    refute Flow.semantic_identity(expression) ==
             Flow.semantic_identity(output_flow(%{value: %{operator: :+, operands: [1, 2]}}))
  end

  @tag obligation: ["jido_action.expression.I1", "jido_action.expression.I2"]
  test "native source and canonical binary operators produce the same Flow model" do
    assert {:ok, from_dsl} =
             ValueParser.parse_condition(
               quote do
                 input(:score) * 2 >= 80 and input(:enabled)
               end
             )

    from_helper =
      Expr.new!(:and, [
        Expr.new!(:>=, [Expr.new!(:*, [Ref.input(:score), 2]), 80]),
        Ref.input(:enabled)
      ])

    assert choice_flow(from_dsl) == choice_flow(from_helper)
  end

  @tag obligation: ["jido_action.expression.I2", "jido_action.expression.I4"]
  test "malformed stored expressions fail with JSON paths and no atom creation" do
    assert {:ok, document, registry} = Codec.encode(output_flow(Expr.new!(:+, [1, 2])))
    unknown = "unknown_operator_#{System.unique_integer([:positive])}"
    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end

    for {record, expected_path} <- [
          {%{"operator" => unknown, "operands" => [1, 2]}, ["output", "$expr", "operator"]},
          {%{"operator" => "+", "operands" => [1]}, ["output", "$expr"]},
          {%{"operator" => "+", "operands" => "invalid"}, ["output", "$expr", "operands"]},
          {%{"operator" => "+", "operands" => [1, 2], "call" => "System.halt"}, ["output", "$expr", "call"]}
        ] do
      assert {:error, error} =
               Codec.decode(%{document | "output" => %{"$expr" => record}}, registry)

      assert error.details.path == expected_path
    end

    assert_raise ArgumentError, fn -> String.to_existing_atom(unknown) end
  end

  @tag obligation: ["jido_action.expression.I3", "jido_action.expression.I4"]
  test "nested invalid expression definitions and evaluation limits stay structured" do
    for invalid <- [
          %Jido.Expr.Operation{operator: :unknown, operands: []},
          %Jido.Expr.Operation{operator: :+, operands: [1 | :tail]},
          Expr.new!(:+, [fn -> 1 end, 2])
        ] do
      assert {:error, _} =
               JidoActionTest.FlowComponent.step(
                 name: "invalid",
                 action: EchoParamsAction,
                 params: %{value: invalid}
               )
    end

    deep = Enum.reduce(1..70, 1, fn _, value -> Expr.new!(:-, [value]) end)

    assert {:error, _} =
             JidoActionTest.FlowComponent.step(
               name: "deep",
               action: EchoParamsAction,
               params: %{value: deep}
             )

    assert {:error, error} =
             Jido.Exec.run(
               output_flow(%{value: Expr.new!(:<>, [Ref.input(:text), Ref.input(:text)])}),
               %{text: String.duplicate("a", 400_000)}
             )

    assert error.details.reason == :max_binary_bytes
    refute Map.has_key?(error.details, :text)
  end

  defp output_flow(output) do
    JidoActionTest.FlowBuilder.new!(
      name: "expression_output",
      components: [JidoActionTest.FlowComponent.step!(name: "seed", action: EchoParamsAction)],
      output: output
    )
  end

  defp choice_flow(condition) do
    JidoActionTest.FlowBuilder.new!(
      name: "expression_choice",
      components: [
        JidoActionTest.FlowComponent.choice!(
          name: "route",
          options: [
            [
              name: "yes",
              condition: condition,
              action: EchoParamsAction,
              params: %{selected: true}
            ]
          ],
          fallback: [action: EchoParamsAction, params: %{selected: false}]
        )
      ],
      output: Ref.result("route")
    )
  end
end
