Code.require_file("../support/flows/components.ex", __DIR__)

defmodule JidoActionTest.Authoring.ComponentsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.{Exec, Expr}
  alias Jido.Flow.{Codec, Ref}
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Authoring.Components

  alias Components.{
    Advance,
    Child,
    ChoiceFlow,
    Decide,
    InvokeFlow,
    HandoffFlow,
    DoubleParent,
    Echo,
    Expand,
    Final,
    GatedMapFlow,
    ParallelFlow
  }

  alias Components.{
    Fold,
    IterateRepeat,
    IterateWhile,
    MapBlock,
    MapCollect,
    MapItem,
    MapKeyword,
    Parent
  }

  alias Components.ReduceFlow

  test "Map keyword and block forms match direct, and JSON, including empty input" do
    params = %{value: Ref.item(), index: Ref.item_index(), item_id: Ref.item_id()}

    component =
      JidoActionTest.FlowComponent.map!(
        name: "items",
        collection: Ref.input(:items),
        action: MapItem,
        params: params
      )

    output = %{items: Ref.result("items")}

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: MapKeyword.name(),
        components: [component],
        output: output
      )

    data = %{
      output: output,
      components: [
        %{
          kind: :map,
          name: "items",
          collection: Jido.Flow.Ref.input(:items),
          action: MapItem,
          params: params
        }
      ],
      name: MapKeyword.name()
    }

    forms = parity(MapKeyword, direct, data)
    assert MapBlock.flow() == direct

    for form <- [MapBlock | forms] do
      assert Exec.run(form, %{items: []}, %{observer: self()}) == {:ok, %{items: []}}
    end

    refute_received {:map_item, _}

    assert {:ok, %{items: mapped}} =
             Exec.run(MapKeyword, %{items: [4, 4, 2]}, %{}, max_concurrency: 3)

    assert Enum.map(mapped, &{&1.value, &1.index}) == [{8, 0}, {8, 1}, {4, 2}]
    assert length(Enum.uniq(Enum.map(mapped, & &1.item_id))) == 3

    for form <- [MapBlock | tl(forms)] do
      assert Exec.run(form, %{items: [4, 4, 2]}, %{}, max_concurrency: 3) ==
               {:ok, %{items: mapped}}
    end
  end

  test "Reduce matches all forms and a non-associative fold runs in source order" do
    component =
      JidoActionTest.FlowComponent.reduce!(
        name: "fold",
        collection: Ref.input(:items),
        initial: %{value: 1},
        action: Fold,
        params: %{acc: Ref.accumulator(:value), item: Ref.item()}
      )

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: ReduceFlow.name(),
        components: [component],
        output: Ref.result("fold")
      )

    data = %{
      output: Jido.Flow.Ref.result("fold"),
      components: [
        %{
          kind: :reduce,
          name: "fold",
          collection: Jido.Flow.Ref.input(:items),
          initial: %{value: 1},
          action: Fold,
          params: %{acc: Jido.Flow.Ref.accumulator(:value), item: Jido.Flow.Ref.item()}
        }
      ],
      name: ReduceFlow.name()
    }

    forms = parity(ReduceFlow, direct, data)

    for form <- forms do
      assert Exec.run(form, %{items: []}, %{observer: self()}) == {:ok, %{value: 1}}
      assert Exec.run(form, %{items: [2, 2, 3]}) == {:ok, %{value: 777}}
    end

    refute_received {:fold, _, _}
    assert Exec.run(ReduceFlow, %{items: [2, 2, 3]}, %{observer: self()}) == {:ok, %{value: 777}}
    assert_receive {:fold, 2, 1}
    assert_receive {:fold, 2, 8}
    assert_receive {:fold, 3, 78}
    refute_received {:fold, _, _}
  end

  test "Map fail-fast does not admit an item after a serial item failure" do
    assert {:error, error} =
             Exec.run(MapKeyword, %{items: [1, :bad, 3]}, %{observer: self()}, max_concurrency: 1)

    assert %{
             type: :execution_error,
             message: "bad map item",
             details: %{node_path: ["items"], item_index: 1}
           } = Jido.Error.to_map(error)

    assert_receive {:map_item, 1}
    assert_receive {:map_item, :bad}
    refute_received {:map_item, 3}
  end

  test "Map keeps input order and item identity when repeated items finish in reverse order" do
    observer = self()

    task =
      Task.async(fn ->
        Exec.run(GatedMapFlow, %{items: ~c"\a\a\t"}, %{observer: observer}, max_concurrency: 3)
      end)

    started =
      for _ <- 1..3, into: %{} do
        assert_receive {:map_started, index, value, item_id, pid}, 5000
        {index, {value, item_id, pid}}
      end

    assert Map.keys(started) |> Enum.sort() == [0, 1, 2]
    assert Enum.map(0..2, fn index -> started[index] |> elem(0) end) == ~c"\a\a\t"
    assert started |> Map.values() |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 3

    for index <- [2, 1, 0] do
      send(started[index] |> elem(2), {:release_map_item, index})
    end

    assert {:ok, %{items: results}} = Task.await(task, 10_000)

    expected =
      for index <- 0..2 do
        {index, started[index] |> elem(0), started[index] |> elem(1)}
      end

    assert Enum.map(results, &{&1.index, &1.value, &1.item_id}) == expected
  end

  test "Map collect-errors returns ordered tagged results for every item" do
    assert {:ok, %{items: [first, bad, last]}} =
             Exec.run(MapCollect, %{items: [1, :bad, 3]}, %{observer: self()}, max_concurrency: 1)

    assert first.status == :ok
    assert first.value.value == 2
    assert bad.status == :error
    assert bad.error.message == "bad map item"
    assert last.status == :ok
    assert last.value.value == 6
    assert_receive {:map_item, 1}
    assert_receive {:map_item, :bad}
    assert_receive {:map_item, 3}
    refute_received {:map_item, _}
  end

  test "Reduce failure stops before the next item" do
    assert {:error, error} = Exec.run(ReduceFlow, %{items: [2, :bad, 3]}, %{observer: self()})
    assert error.details.node_path == ["fold"]
    assert_receive {:fold, 2, 1}
    assert_receive {:fold, :bad, 8}
    refute_received {:fold, 3, _}
  end

  test "fixed and bounded Iterate forms match all authoring forms" do
    state =
      JidoActionTest.FlowComponent.state!(
        schema:
          IterateRepeat.flow().components
          |> Map.fetch!("counter")
          |> Map.fetch!(:state)
          |> Map.fetch!(:schema),
        initial: %{count: 0},
        update: %{count: Ref.body_result(:count)}
      )

    params = %{
      count: Ref.state(:count),
      index: Ref.iteration_index(),
      previous: Ref.body_result()
    }

    output = %{counter: Ref.result("counter")}

    for {module, completion, maximum, input, iterations} <- [
          {IterateRepeat, Expr.new!(:>=, [Ref.iteration_index(), 3]), 3, %{}, 3},
          {IterateWhile, Expr.new!(:not, [Expr.new!(:<, [Ref.state(:count), Ref.input(:limit)])]), 4, %{limit: 3}, 3}
        ] do
      direct =
        JidoActionTest.FlowBuilder.new!(
          name: module.name(),
          components: [
            JidoActionTest.FlowComponent.iterate!(
              name: "counter",
              action: Advance,
              params: params,
              state: state,
              completion: completion,
              max_iterations: maximum
            )
          ],
          output: output
        )

      data = %{
        output: output,
        components: [
          %{
            kind: :iterate,
            name: "counter",
            action: Advance,
            params: params,
            state: state,
            completion: completion,
            max_iterations: maximum
          }
        ],
        name: module.name()
      }

      for form <- parity(module, direct, data) do
        assert {:ok, %{counter: %{iterations: ^iterations, state: state_value}}} =
                 Exec.run(form, input)

        assert state_value == %{count: 3}
      end
    end

    assert {:ok, %{counter: %{iterations: 0, state: %{count: 0}}}} =
             Exec.run(IterateWhile, %{limit: 0}, %{observer: self()})

    refute_received {:iteration, _, _, _}
    assert {:ok, _} = Exec.run(IterateRepeat, %{}, %{observer: self()})
    assert_receive {:iteration, 0, 0, nil}
    assert_receive {:iteration, 1, 1, %{count: 1, index: 0}}
    assert_receive {:iteration, 2, 2, %{count: 2, index: 1}}
    refute_received {:iteration, _, _, _}
  end

  test "bounded Iterate stops at its limit without one extra body call" do
    assert {:error, error} = Exec.run(IterateWhile, %{limit: 9}, %{observer: self()})
    assert error.details.node == "counter"
    assert error.phase == :iterate_exhaustion

    for index <- 0..3 do
      assert_receive {:iteration, ^index, ^index, _previous}
    end

    refute_received {:iteration, 4, _, _}
    assert {:error, body_error} = Exec.run(IterateRepeat, %{}, %{observer: self(), fail_at: 1})
    assert body_error.details.node_path == ["counter"]
    assert_receive {:iteration, 0, 0, nil}
    assert_receive {:iteration, 1, 1, %{count: 1, index: 0}}
    refute_received {:iteration, 2, _, _}
  end

  test "Subflow parent and child preserve input, output, context, and schema" do
    output = %{child: Ref.result("child")}

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: Parent.name(),
        components: [
          JidoActionTest.FlowComponent.subflow!(
            name: "child",
            flow: Child,
            params: %{value: Ref.input(:value)}
          )
        ],
        output: output
      )

    data = %{
      output: output,
      components: [
        %{
          kind: :subflow,
          flow: Child,
          name: "child",
          params: %{value: Jido.Flow.Ref.input(:value)}
        }
      ],
      name: Parent.name()
    }

    for form <- parity(Parent, direct, data) do
      assert Exec.run(form, %{value: 5}, %{label: "shared"}) ==
               {:ok, %{child: %{value: 5, label: "shared"}}}

      assert {:error, error} = Exec.run(form, %{value: "bad"}, %{label: "shared"})
      assert error.details.node_path == ["child"]
    end
  end

  test "two uses of one child keep separate values and error paths" do
    assert Exec.run(DoubleParent, %{left: 1, right: 2}, %{label: "shared"}) ==
             {:ok, %{left: %{value: 1, label: "shared"}, right: %{value: 2, label: "shared"}}}

    assert {:error, error} = Exec.run(DoubleParent, %{left: 1, right: "bad"}, %{label: "shared"})
    assert error.details.node_path == ["right"]
  end

  test "Choice matches all forms, selects first matching option, and falls back" do
    options = [
      JidoActionTest.FlowComponent.option!(
        name: "urgent",
        condition: Expr.new!(:>=, [Ref.input(:score), 90]),
        action: Echo,
        params: %{route: :urgent}
      ),
      JidoActionTest.FlowComponent.option!(
        name: "priority",
        condition: Expr.new!(:>=, [Ref.input(:score), 50]),
        action: Echo,
        params: %{route: :priority}
      )
    ]

    fallback = JidoActionTest.FlowComponent.fallback!(action: Echo, params: %{route: :standard})

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: ChoiceFlow.name(),
        components: [
          JidoActionTest.FlowComponent.choice!(
            name: "route",
            options: options,
            fallback: fallback
          )
        ],
        output: Ref.result("route")
      )

    data = %{
      output: Jido.Flow.Ref.result("route"),
      components: [%{kind: :choice, name: "route", options: options, fallback: fallback}],
      name: ChoiceFlow.name()
    }

    for form <- parity(ChoiceFlow, direct, data),
        {score, route} <- [{100, :urgent}, {70, :priority}, {10, :standard}] do
      assert Exec.run(form, %{score: score}) == {:ok, %{route: route}}
    end
  end

  test "Invoke matches all forms and continues to Action or Flow" do
    params = %{mode: Ref.input(:mode), value: Ref.input(:value), target: Ref.input(:target)}

    direct =
      JidoActionTest.FlowBuilder.new!(
        name: InvokeFlow.name(),
        components: [
          JidoActionTest.FlowComponent.invoke!(
            name: "route",
            decision: Decide,
            expander: Expand,
            params: params
          )
        ],
        output: Ref.result("route")
      )

    data = %{
      output: Jido.Flow.Ref.result("route"),
      components: [
        %{kind: :invoke, name: "route", decision: Decide, expander: Expand, params: params}
      ],
      name: InvokeFlow.name()
    }

    for form <- parity(InvokeFlow, direct, data) do
      for {mode, target, expected} <- [
            {:finish, nil, %{value: 5, label: "ctx"}},
            {:continue, Final, %{value: 6, label: "ctx"}},
            {:continue, Components.FinalFlow, %{value: 6, label: "ctx"}}
          ] do
        assert Exec.run(form, %{mode: mode, value: 5, target: target}, %{label: "ctx"}) ==
                 {:ok, expected}
      end
    end
  end

  test "Parallel matches DSL, data, and stored forms and rejects duplicate Action names" do
    data = %{
      name: ParallelFlow.name(),
      components: [
        %{
          kind: :parallel,
          name: "tools",
          actions: [%{name: "echo", action: Echo, params: %{value: Ref.input(:value)}}]
        }
      ],
      output: %{tools: Ref.result("tools")}
    }

    assert {:ok, direct} = JidoActionTest.FlowBuilder.new(data)
    assert ParallelFlow.flow() == direct
    assert {:ok, document, registry} = Codec.encode(direct)
    assert {:ok, ^direct} = Codec.decode(document, registry)

    duplicate =
      put_in(data, [:components, Access.at(0), :actions], [
        %{name: "echo", action: Echo, params: %{}},
        %{name: "echo", action: Echo, params: %{}}
      ])

    assert {:error,
            %{
              message: "parallel Action names must be unique",
              details: %{name: "echo", path: [:components, 0, :actions]}
            }} =
             JidoActionTest.FlowBuilder.new(duplicate)
  end

  test "Handoff matches DSL, data, and stored forms and requires its complete result" do
    data = %{
      name: HandoffFlow.name(),
      components: [
        %{kind: :handoff, name: "route", selector: Expand, params: Ref.input([])}
      ],
      output: Ref.result("route")
    }

    assert {:ok, direct} = JidoActionTest.FlowBuilder.new(data)
    assert HandoffFlow.flow() == direct
    assert {:ok, document, registry} = Codec.encode(direct)
    assert {:ok, ^direct} = Codec.decode(document, registry)

    assert {:error,
            %{
              message: "Flow output must be the complete Handoff result",
              details: %{handoff: "route", path: [:output]}
            }} =
             data
             |> Map.put(:output, Ref.result("route", :value))
             |> JidoActionTest.FlowBuilder.new()
  end

  defp parity(module, direct, data) do
    assert module.flow() == direct
    assert {:ok, built} = JidoActionTest.FlowBuilder.new(data)
    assert built == direct
    assert {:ok, document, registry} = Codec.encode(direct)
    assert {:ok, restored} = Codec.decode(document |> JSON.encode!() |> JSON.decode!(), registry)
    assert restored == direct
    [module, direct, built, restored]
  end
end
