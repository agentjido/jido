defmodule JidoActionTest.Flow.DSL.ExprFlowTest do
  use ExUnit.Case, async: true
  alias Jido.Expr
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.Actions.EchoParamsAction

  defmodule Parity do
    use Jido.Flow, name: "calculated"

    flow do
      step("load", action: EchoParamsAction, params: %{quantity: input(:quantity) + 1})

      output(%{
        total: result("load", :quantity) * input(:price),
        label: context(:prefix) <> input(:name)
      })
    end
  end

  defmodule Child do
    use Jido.Flow, name: "expression_child"

    flow do
      step("echo", action: EchoParamsAction, params: %{value: input(:value) * 2})
      output(result("echo"))
    end
  end

  defmodule Mixed do
    use Jido.Flow, name: "expression_positions"

    flow do
      map("mapped",
        collection: [input(:start) + 1, 2],
        action: EchoParamsAction,
        params: %{value: item() * 2, index: item_index() + 1, id: "item-" <> item_id()}
      )

      reduce("reduced",
        collection: result("mapped"),
        initial: %{value: input(:start) - 1},
        action: EchoParamsAction,
        params: %{value: accumulator(:value) + item(:value)}
      )

      iterate("loop") do
        state(Zoi.map(), initial: %{count: input(:start) - 1, done: false})
        action(EchoParamsAction)
        params(%{count: state(:count) + 1, index: iteration_index() + 1})
        update(%{count: body_result(:count), done: body_result(:count) >= 3})
        while(not state(:done))
        max_iterations(5)
      end

      step("inline", total <- result("reduced", :value)) do
        {:ok, %{value: total + 1}}
      end

      step("child", action: Child, params: %{value: result("inline", :value) + 1})

      choice("route") do
        option("enabled",
          condition: input(:enabled) and not context(:paused),
          action: EchoParamsAction,
          params: %{value: result("child", :value) / 2}
        )

        otherwise(action: EchoParamsAction, params: %{value: -input(:start)})
      end

      output(%{
        value: result("route", :value),
        loop: result("loop", :state),
        eligible: expr(input(:enabled) and result("inline", :value) >= 9)
      })
    end
  end

  defmodule Invoked do
    use Jido.Flow, name: "expression_invoke"

    flow do
      invoke "finish",
        decision: EchoParamsAction,
        expander: EchoParamsAction,
        params: %{value: min(input(:value) + 1, 10)}

      output(result("finish"))
    end
  end

  test "module DSL equals runtime authoring with shared helper syntax" do
    import Jido.Expr, only: [expr: 1]
    quantity = Ref.input(:quantity)
    load = Ref.result("load", :quantity)
    price = Ref.input(:price)
    prefix = Ref.context(:prefix)
    name = Ref.input(:name)
    params = %{quantity: expr(^quantity + 1)}
    output = %{total: expr(^load * ^price), label: expr(^prefix <> ^name)}

    assert {:ok, built} =
             JidoActionTest.FlowBuilder.new(%{
               output: output,
               components: [
                 %{kind: :step, name: "load", action: EchoParamsAction, params: params}
               ],
               name: "calculated"
             })

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "calculated",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "load",
            action: EchoParamsAction,
            params: params
          )
        ],
        output: output
      )

    assert Parity.flow() == built
    assert direct == built
    assert {:ok, document, registry} = Codec.encode(built)
    assert {:ok, restored} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)
    assert restored == built
  end

  test "expressions work through local scopes, inline bodies, child Flows, and Choice" do
    assert {:ok, document, registry} = Codec.encode(Mixed.flow())
    assert {:ok, restored} = Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

    for flow <- [Mixed, restored] do
      assert Jido.Exec.run(flow, %{start: 1, enabled: true}, %{paused: false}) ==
               {:ok, %{value: 10.0, loop: %{count: 3, done: true}, eligible: true}}
    end

    assert Jido.Exec.run(Invoked, %{value: 20}) == {:ok, %{value: 10}}
  end

  test "Boolean expressions can supply calculated parameter values" do
    step =
      JidoActionTest.FlowComponent.step!(
        name: "echo",
        action: EchoParamsAction,
        params: %{eligible: Expr.new!(:>=, [Expr.new!(:*, [Ref.input(:score), 2]), 80])}
      )

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "condition_value",
        components: [step],
        output: Ref.result("echo")
      )

    assert Jido.Exec.run(flow, %{score: 40}) == {:ok, %{eligible: true}}
  end

  test "Step keyword and block fields preserve the same expression AST" do
    flows =
      for {module, declaration} <- [
            {StepKeywordQuotedFields,
             "step \"echo\",\n  action: JidoActionTest.Fixtures.Actions.EchoParamsAction,\n  params: %{value: input(:value) + 1, nested: [nil, %{}]}\n"},
            {StepBlockQuotedFields,
             "step \"echo\" do\n  action JidoActionTest.Fixtures.Actions.EchoParamsAction\n  params %{value: input(:value) + 1, nested: [nil, %{}]}\nend\n"}
          ] do
        Code.compile_string("defmodule #{inspect(module)} do
  use Jido.Flow, name: \"step_quoted_fields\"
  flow do
    #{declaration}
    output result(\"echo\")
  end
end
")
        module.flow()
      end

    assert [flow, flow] = flows
    assert Jido.Exec.run(flow, %{value: 2}) == {:ok, %{value: 3, nested: [nil, %{}]}}
  end

  test "Map keyword and block fields preserve nested expressions and literal data" do
    declarations = [
      {MapKeywordFields,
       "map \"mapped\",\n  collection: [input(:start) + 1, 2],\n  action: JidoActionTest.Fixtures.Actions.EchoParamsAction,\n  params: %{nested: [item() * 2, %{empty: [], absent: nil}]},\n  on_error: :collect_errors\n"},
      {MapBlockFields,
       "map \"mapped\" do\n  collection [input(:start) + 1, 2]\n  action JidoActionTest.Fixtures.Actions.EchoParamsAction\n  params %{nested: [item() * 2, %{empty: [], absent: nil}]}\n  on_error :collect_errors\nend\n"}
    ]

    flows =
      for {module, declaration} <- declarations do
        Code.compile_string("defmodule #{inspect(module)} do
  use Jido.Flow, name: \"map_fields\"
  flow do
    #{declaration}
    output %{items: result(\"mapped\")}
  end
end
")
        module.flow()
      end

    assert [flow, flow] = flows

    assert %{
             kind: :map,
             call: %{target: EchoParamsAction, params: _params},
             on_error: :collect_errors
           } = flow.components["mapped"]

    assert Jido.Exec.run(flow, %{start: 2}) ==
             {:ok,
              %{
                items: [
                  %{status: :ok, value: %{nested: [6, %{empty: [], absent: nil}]}},
                  %{status: :ok, value: %{nested: [4, %{empty: [], absent: nil}]}}
                ]
              }}
  end

  test "Map fields reject literal tuples instead of treating them as reference AST" do
    for {module, declaration} <- [
          {MapKeywordTuple,
           "map \"mapped\", action: JidoActionTest.Fixtures.Actions.EchoParamsAction,\n  collection: [], params: %{value: {:input, [], []}}\n"},
          {MapBlockTuple,
           "map \"mapped\" do\n  action JidoActionTest.Fixtures.Actions.EchoParamsAction\n  collection []\n  params %{value: {:input, [], []}}\nend\n"}
        ] do
      assert_raise CompileError, ~r/unsupported Flow expression/, fn ->
        Code.compile_string("defmodule #{inspect(module)} do
  use Jido.Flow, name: \"map_tuple\"
  flow do
    #{declaration}
    output %{items: result(\"mapped\")}
  end
end
")
      end
    end
  end
end
