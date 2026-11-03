defmodule JidoActionTest.Flow.ConditionNormalizationTest do
  use ExUnit.Case, async: true

  alias Jido.Expr
  alias Jido.Flow
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.DSL.ValueParser
  alias Jido.Error.ValidationError
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  test "Boolean literals and references keep one shape across authoring forms" do
    cases = [
      {quote(do: true), true, %{}, true},
      {quote(do: false), false, %{}, false},
      {quote(do: input(:enabled)), Ref.input(:enabled), %{enabled: true}, true},
      {quote(do: input(:enabled)), Ref.input(:enabled), %{enabled: false}, false}
    ]

    for {{source, value, input, expected}, index} <- Enum.with_index(cases) do
      assert {:ok, ^value} = ValueParser.parse_condition(source)
      assert {:ok, ^value} = Flow.Value.condition(value, :flow)
      direct = choice_flow(value)

      for flow <- [
            direct,
            data_flow(value),
            module_flow(Module.concat(__MODULE__, "Direct#{index}"), source),
            round_trip(direct)
          ] do
        assert flow == direct
        assert Jido.Exec.run(flow, input) == {:ok, %{selected: expected}}
      end
    end
  end

  test "nested and, or, and not keep one canonical expression shape" do
    source =
      quote do
        true and (not false or input(:enabled))
      end

    expression =
      Expr.new!(:and, [
        true,
        Expr.new!(:or, [Expr.new!(:not, [false]), Ref.input(:enabled)])
      ])

    assert {:ok, ^expression} = ValueParser.parse_condition(source)
    assert {:ok, ^expression} = Flow.Value.condition(expression, :flow)
    direct = choice_flow(expression)

    for flow <- [
          direct,
          data_flow(expression),
          module_flow(Module.concat(__MODULE__, "Nested"), source),
          round_trip(direct)
        ] do
      assert flow == direct
      assert Jido.Exec.run(flow, %{enabled: false}) == {:ok, %{selected: true}}
    end
  end

  test "skipped operands work in Choice, Iterate, and data fields" do
    cases = [
      {quote(do: false and 1), Expr.new!(:and, [false, 1]), false},
      {quote(do: true or nil), Expr.new!(:or, [true, nil]), true},
      {quote(do: false and 1 + 1), Expr.new!(:and, [false, Expr.new!(:+, [1, 1])]), false}
    ]

    for {{source, expression, expected}, index} <- Enum.with_index(cases) do
      assert Jido.Exec.run(output_flow(expression)) == {:ok, %{selected: expected}}
      assert {:ok, ^expression} = ValueParser.parse_condition(source)
      direct = choice_flow(expression)

      for flow <- [
            direct,
            data_flow(expression),
            module_flow(Module.concat(__MODULE__, "Skipped#{index}"), source),
            round_trip(direct)
          ] do
        assert flow == direct
        assert Jido.Exec.run(flow) == {:ok, %{selected: expected}}
      end

      iterator = iterator_flow(Expr.new!(:or, [expression, Ref.state(:done)]))
      iterations = if expected, do: 0, else: 1

      for flow <- [iterator, round_trip(iterator)] do
        assert {:ok, %{iterations: ^iterations}} = Jido.Exec.run(flow)
      end
    end
  end

  test "non-Boolean expression results remain data and fail at condition boundaries" do
    for {source, expression, expected} <- [
          {quote(do: true and 1), Expr.new!(:and, [true, 1]), 1},
          {quote(do: false or nil), Expr.new!(:or, [false, nil]), nil}
        ] do
      assert {:ok, ^expression} = Flow.Value.condition(expression, :any)
      assert {:ok, ^expression} = ValueParser.parse_condition(source)
      assert Jido.Exec.run(output_flow(expression)) == {:ok, %{selected: expected}}

      for {flow, phase} <- [
            {choice_flow(expression), :choice_condition},
            {iterator_flow(expression), :iterate_completion}
          ] do
        assert {:error, error} = Jido.Exec.run(flow)
        assert error.details.reason == :invalid_boolean_operand
        assert error.phase == phase
        assert error.details.expression_path == []
        assert error.details.retry == false
      end
    end
  end

  test "skipped operands still require portable data and valid reference scopes" do
    for expression <- [
          Expr.new!(:and, [false, Ref.item()]),
          Expr.new!(:or, [true, Ref.body_result()]),
          Expr.new!(:and, [false, fn -> true end])
        ] do
      assert {:error, %ValidationError{}} = Flow.Value.condition(expression, :flow)
    end

    assert {:error, %ValidationError{}} =
             Flow.Value.condition(Expr.new!(:or, [true, Ref.item()]), :iterate_completion)

    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(
               name: "unknown_skipped_result",
               components: [choice(Expr.new!(:and, [false, Ref.result("missing")]))],
               output: Ref.result("route")
             )

    assert error.details.component == "missing"
  end

  test "operation trees retain construction limits in conditions and data fields" do
    comparisons = List.duplicate(Expr.new!(:==, [1, 1]), 4_000)
    wide = balanced_and(comparisons)

    cases = [
      {Enum.reduce(1..65, true, fn _, child ->
         %Jido.Expr.Operation{operator: :not, operands: [child]}
       end), :max_depth},
      {wide, :max_nodes},
      {%Jido.Expr.Operation{operator: :==, operands: [String.duplicate("x", 1_048_577), ""]}, :max_binary_bytes},
      {%Jido.Expr.Operation{operator: :==, operands: [Bitwise.bsl(1, 4096), 0]}, :max_integer_bits}
    ]

    for {expression, reason} <- cases do
      assert {:error, error} = Flow.Value.condition(expression, :any)
      assert error.details.reason == reason
      assert {:error, error} = Flow.Value.normalize(%{nested: expression})
      assert error.details.reason == reason
    end
  end

  test "conditions and output values share one runtime budget for resolved data" do
    expression = Expr.new!(:==, [Ref.input(:data), Ref.input(:data)])

    for flow <- [choice_flow(expression), iterator_flow(expression), output_flow(expression)] do
      assert {:error, error} = Jido.Exec.run(flow, %{data: String.duplicate("x", 300_000)})
      assert error.details.reason == :max_binary_bytes
      assert error.details.retry == false
    end
  end

  test "reference names normalize through nested operation operands" do
    expression = %Jido.Expr.Operation{
      operator: :==,
      operands: [%Ref{source: :result, component: :seed, path: []}, %{value: 1}]
    }

    assert {:ok, %Jido.Expr.Operation{operands: [%Ref{component: "seed"}, _]}} =
             Flow.Value.condition(expression, :any)

    assert {:error, error} =
             Flow.Value.normalize(%{
               outer: [
                 %Jido.Expr.Operation{
                   operator: :not,
                   operands: [%Jido.Expr.Operation{operator: :unknown, operands: [1, 1]}]
                 }
               ]
             })

    assert error.details.path == [:outer, 0, :operands, 0]
  end

  test "stored conditions use one expression tag and native operator names" do
    flow = choice_flow(Expr.new!(:>=, [Ref.input(:score), 1]))
    assert {:ok, document, registry} = Codec.encode(flow)

    condition =
      get_in(document, ["components", Access.at(0), "options", Access.at(0), "condition"])

    assert get_in(condition, ["$expr", "operator"]) == ">="
    assert [%{"$ref" => _ref}, 1] = get_in(condition, ["$expr", "operands"])

    assert {:ok, ^flow} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert Jido.Exec.run(flow, %{score: 1}) == {:ok, %{selected: true}}
  end

  defp balanced_and([expression]), do: expression

  defp balanced_and(expressions) do
    expressions
    |> Enum.chunk_every(2)
    |> Enum.map(fn
      [left, right] -> %Jido.Expr.Operation{operator: :and, operands: [left, right]}
      [expression] -> expression
    end)
    |> balanced_and()
  end

  defp choice(condition) do
    JidoActionTest.FlowComponent.choice!(
      name: "route",
      options: [
        %{name: "yes", condition: condition, action: EchoParamsAction, params: %{selected: true}}
      ],
      fallback: [action: EchoParamsAction, params: %{selected: false}]
    )
  end

  defp choice_flow(condition) do
    JidoActionTest.FlowBuilder.new!(
      name: "condition_parity",
      components: [choice(condition)],
      output: Ref.result("route")
    )
  end

  defp data_flow(condition) do
    JidoActionTest.FlowBuilder.new!(%{
      name: "condition_parity",
      components: [
        %{
          kind: :choice,
          name: "route",
          options: [
            %{
              name: "yes",
              condition: condition,
              action: EchoParamsAction,
              params: %{selected: true}
            }
          ],
          fallback: %{action: EchoParamsAction, params: %{selected: false}}
        }
      ],
      output: Ref.result("route")
    })
  end

  defp module_flow(module, source) do
    body =
      quote do
        use Jido.Flow, name: "condition_parity"

        flow do
          choice("route") do
            option("yes",
              condition: unquote(source),
              action: unquote(EchoParamsAction),
              params: %{selected: true}
            )

            otherwise(action: unquote(EchoParamsAction), params: %{selected: false})
          end

          output(result("route"))
        end
      end

    Module.create(module, body, Macro.Env.location(__ENV__))
    module.flow()
  end

  defp output_flow(expression) do
    JidoActionTest.FlowBuilder.new!(
      name: "condition_output",
      components: [JidoActionTest.FlowComponent.step!(name: "seed", action: EchoParamsAction)],
      output: %{selected: expression}
    )
  end

  defp iterator_flow(completion) do
    iterator =
      JidoActionTest.FlowComponent.iterate!(
        name: "loop",
        action: EchoParamsAction,
        state: [schema: Jido.Joi.map(), initial: %{done: false}, update: %{done: true}],
        completion: completion,
        max_iterations: 1
      )

    JidoActionTest.FlowBuilder.new!(
      name: "condition_iterator",
      components: [iterator],
      output: Ref.result("loop")
    )
  end

  defp round_trip(flow) do
    assert {:ok, document, registry} = Codec.encode(flow)
    assert {:ok, restored} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    restored
  end
end
