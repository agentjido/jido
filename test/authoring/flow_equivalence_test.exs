Code.require_file("support/jido_flow/greeting.ex", __DIR__)
Code.require_file("support/jido_flow/components.ex", __DIR__)

defmodule Jido.Authoring.FlowEquivalenceTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.{Expr, Flow}
  alias Jido.Flow.Ref
  alias Jido.Test.Flow.Codec
  alias Jido.Test.Flow.Authoring.Greeting
  alias Jido.Test.Flow.Authoring.Components

  test "DSL, independent Map, and fixed JSON produce the same complete Flow definition" do
    expected = Greeting.Flow.flow()

    data = %{
      name: Greeting.Flow.name(),
      schema: Greeting.Flow.schema(),
      output_schema: Greeting.Flow.output_schema(),
      components: [
        %{
          kind: :step,
          name: "normalize",
          action: Greeting.Normalize,
          params: %{name: Ref.input(:name)}
        },
        %{
          kind: :step,
          name: "greet",
          action: Greeting.Greet,
          params: %{name: Ref.result("normalize", :name)}
        }
      ],
      output: Ref.result("greet")
    }

    assert {:ok, from_map} = Jido.Test.Flow.Builder.new(data)
    assert from_map === expected

    assert {:ok, encoded_document, catalog} = Codec.encode(expected)
    fixture = Path.join(__DIR__, "support/complete_flow.json")
    document = fixture |> File.read!() |> JSON.decode!()
    assert encoded_document === document
    assert {:ok, from_json} = Codec.decode(document, catalog)
    assert from_json === expected
  end

  test "each public Flow component has the same DSL, Map, and JSON definition" do
    for {module, data} <- component_cases() do
      expected = module.flow()
      assert {:ok, from_map} = Jido.Test.Flow.Builder.new(data)
      assert from_map === expected
      assert {:ok, document, catalog} = Codec.encode(expected)
      assert {:ok, from_json} = Codec.decode(document |> JSON.encode!() |> JSON.decode!(), catalog)
      assert from_json === expected
      assert Flow.to_map(from_json) === Flow.to_map(expected)
    end
  end

  defp component_cases do
    map_params = %{value: Ref.item(), index: Ref.item_index(), item_id: Ref.item_id()}

    iterate_state =
      Jido.Test.Flow.Component.state!(
        schema: Jido.Joi.object(%{count: Jido.Joi.integer()}),
        initial: %{count: 0},
        update: %{count: Ref.body_result(:count)}
      )

    iterate_params = %{
      count: Ref.state(:count),
      index: Ref.iteration_index(),
      previous: Ref.body_result()
    }

    choice_options = [
      Jido.Test.Flow.Component.option!(
        name: "urgent",
        condition: Expr.new!(:>=, [Ref.input(:score), 90]),
        action: Components.Echo,
        params: %{route: :urgent}
      ),
      Jido.Test.Flow.Component.option!(
        name: "priority",
        condition: Expr.new!(:>=, [Ref.input(:score), 50]),
        action: Components.Echo,
        params: %{route: :priority}
      )
    ]

    choice_fallback =
      Jido.Test.Flow.Component.fallback!(
        action: Components.Echo,
        params: %{route: :standard}
      )

    [
      {Components.MapKeyword,
       %{
         name: Components.MapKeyword.name(),
         components: [
           %{
             kind: :map,
             name: "items",
             collection: Ref.input(:items),
             action: Components.MapItem,
             params: map_params
           }
         ],
         output: %{items: Ref.result("items")}
       }},
      {Components.ReduceFlow,
       %{
         name: Components.ReduceFlow.name(),
         components: [
           %{
             kind: :reduce,
             name: "fold",
             collection: Ref.input(:items),
             initial: %{value: 1},
             action: Components.Fold,
             params: %{acc: Ref.accumulator(:value), item: Ref.item()}
           }
         ],
         output: Ref.result("fold")
       }},
      {Components.IterateRepeat,
       %{
         name: Components.IterateRepeat.name(),
         components: [
           %{
             kind: :iterate,
             name: "counter",
             action: Components.Advance,
             params: iterate_params,
             state: iterate_state,
             completion: Expr.new!(:>=, [Ref.iteration_index(), 3]),
             max_iterations: 3
           }
         ],
         output: %{counter: Ref.result("counter")}
       }},
      {Components.Parent,
       %{
         name: Components.Parent.name(),
         components: [
           %{
             kind: :subflow,
             name: "child",
             flow: Components.Child,
             params: %{value: Ref.input(:value)}
           }
         ],
         output: %{child: Ref.result("child")}
       }},
      {Components.ChoiceFlow,
       %{
         name: Components.ChoiceFlow.name(),
         components: [
           %{
             kind: :choice,
             name: "route",
             options: choice_options,
             fallback: choice_fallback
           }
         ],
         output: Ref.result("route")
       }},
      {Components.InvokeFlow,
       %{
         name: Components.InvokeFlow.name(),
         components: [
           %{
             kind: :invoke,
             name: "route",
             decision: Components.Decide,
             expander: Components.Expand,
             params: %{mode: Ref.input(:mode), value: Ref.input(:value), target: Ref.input(:target)}
           }
         ],
         output: Ref.result("route")
       }},
      {Components.ParallelFlow,
       %{
         name: Components.ParallelFlow.name(),
         components: [
           %{
             kind: :parallel,
             name: "tools",
             actions: [
               %{name: "echo", action: Components.Echo, params: %{value: Ref.input(:value)}}
             ]
           }
         ],
         output: %{tools: Ref.result("tools")}
       }},
      {Components.HandoffFlow,
       %{
         name: Components.HandoffFlow.name(),
         components: [
           %{
             kind: :handoff,
             name: "route",
             selector: Components.Expand,
             params: Ref.input([])
           }
         ],
         output: Ref.result("route")
       }}
    ]
  end
end
