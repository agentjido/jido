defmodule Jido.Flow.ComponentValidationTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Definition
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref
  alias Jido.Flow.Value
  alias JidoActionTest.Fixtures.Actions.Add
  alias JidoActionTest.Fixtures.NestedFlow

  test "legacy Condition records are rejected in condition and expression fields" do
    legacy = %{__struct__: Jido.Flow.Condition, operator: :==, operands: [1, 1]}

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(choice(%{name: "old", condition: legacy, action: Add}))

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(%{
               kind: :iterate,
               name: "old",
               action: Add,
               state: %{initial: %{}, update: %{}},
               completion: legacy,
               max_iterations: 1
             })

    assert {:error, %InvalidDefinitionError{details: %{path: [:call, :params, :value, :operands, 1]}}} =
             Definition.component(%{
               kind: :step,
               name: "old",
               action: Add,
               params: %{value: Jido.Expr.new!(:and, [false, legacy])}
             })
  end

  test "all authoring forms normalize to tagged maps and call records" do
    for attrs <- component_attrs() do
      assert {:ok, {name, %{kind: kind} = node}} = Definition.component(attrs)
      assert name == attrs.name
      assert kind in [:call, :choice, :map, :reduce, :iterate, :invoke]
      assert is_map(node)

      for {_role, call, _params} <- Definition.calls(node) do
        assert %{kind: target_kind, target: target} = call
        assert target_kind in [:action, :flow]
        assert is_atom(target)
        refute is_struct(call)
        assert Map.keys(call) -- [:kind, :target, :params] == []
      end
    end

    assert {:ok, {"step", %{kind: :call, call: %{kind: :action, params: %{}}}}} =
             Definition.component(%{kind: :step, name: "step", action: Add})

    assert {:ok, {"subflow", %{kind: :call, call: %{kind: :flow, params: %{}}}}} =
             Definition.component(%{kind: :subflow, name: "subflow", flow: NestedFlow})

    assert {:error, %InvalidDefinitionError{}} = Definition.component(%{legacy: true})
    assert {:error, %InvalidDefinitionError{}} = Definition.component(:invalid)
  end

  test "params scopes accept only their native local references" do
    assert {:ok, {"map", %{kind: :map}}} =
             Definition.component(%{
               kind: :map,
               name: "map",
               collection: [],
               action: Add,
               params: %{item: Ref.item()}
             })

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(%{
               kind: :step,
               name: "step",
               action: Add,
               params: %{item: Ref.item()}
             })

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(%{
               kind: :reduce,
               name: "reduce",
               collection: [],
               initial: %{},
               action: Add,
               params: %{state: Ref.state()}
             })
  end

  test "metadata uses only portable data" do
    assert :ok = Value.validate_object(%{"owner" => "team", 1 => [:ready]})

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(%{
               kind: :step,
               name: "step",
               action: Add,
               meta: %{fun: fn -> :bad end}
             })

    assert {:error, %InvalidDefinitionError{}} =
             Definition.component(%{
               kind: :step,
               name: "step",
               action: Add,
               meta: %{pid: self()}
             })
  end

  test "all canonical components use only needs for control dependencies" do
    for attrs <- component_attrs() do
      assert {:ok, {_name, default}} = Definition.component(attrs)
      assert default.needs == []

      assert {:ok, {_name, component}} =
               attrs
               |> Map.put(:needs, [:second, "first"])
               |> Definition.component()

      assert component.needs == ["second", "first"]

      semantic_map = Definition.component_to_definition({attrs.name, component})
      assert semantic_map.needs == ["second", "first"]
      refute Map.has_key?(semantic_map, :after)

      assert {:error, %InvalidDefinitionError{message: message}} =
               attrs
               |> Map.put(:after, [])
               |> Definition.component()

      assert message =~ "unknown"
      assert message =~ "after"

      for {value, expected_message} <- [
            {"first", "component needs must be a list"},
            {["first" | :tail], "component needs must be a proper list"},
            {[nil], "component needs must contain component names"},
            {["first", "first"], "component needs contains a duplicate"}
          ] do
        assert {:error, %InvalidDefinitionError{message: ^expected_message}} =
                 attrs
                 |> Map.put(:needs, value)
                 |> Definition.component()
      end
    end
  end

  test "effective dependencies combine and de-duplicate needs and result references" do
    assert {:ok, {"step", step}} =
             Definition.component(%{
               kind: :step,
               name: "step",
               action: Add,
               params: %{value: Ref.result("source")},
               needs: ["gate", "source"]
             })

    assert Definition.needs(step) == ["gate", "source"]
    assert Definition.reference_dependencies(step) == ["source"]
    assert Definition.effective_dependencies(step) == ["gate", "source"]
  end

  test "Choice option and fallback names are not dependency targets" do
    choice = choice(%{name: "yes", condition: Jido.Expr.new!(:==, [true, true]), action: Add})
    dependent = %{kind: :step, name: "dependent", action: Add, needs: ["route"]}

    assert {:ok, _flow} =
             Jido.Flow.new(%{
               name: "valid_choice_dependency",
               components: [choice, dependent],
               output: Ref.result("dependent")
             })

    for invalid_target <- ["yes", "fallback"] do
      invalid_choice = Map.put(choice, :needs, [invalid_target])

      assert {:error,
              %InvalidDefinitionError{
                message: "Flow reference points to an unknown component",
                details: %{owner: "route", component: ^invalid_target}
              }} =
               Jido.Flow.new(%{
                 name: "invalid_choice_dependency",
                 components: [invalid_choice],
                 output: Ref.result("route")
               })
    end
  end

  test "needs keep unknown, self, and cycle graph validation" do
    unknown = %{kind: :step, name: "one", action: Add, needs: ["missing"]}

    assert {:error,
            %InvalidDefinitionError{
              message: "Flow reference points to an unknown component",
              details: %{owner: "one", component: "missing"}
            }} =
             Jido.Flow.new(%{
               name: "unknown_dependency",
               components: [unknown],
               output: Ref.result("one")
             })

    assert {:error, %InvalidDefinitionError{message: "flow dependency graph contains a cycle"}} =
             Jido.Flow.new(%{
               name: "self_dependency",
               components: [%{kind: :step, name: "one", action: Add, needs: ["one"]}],
               output: Ref.result("one")
             })

    assert {:error,
            %InvalidDefinitionError{
              message: "flow dependency graph contains a cycle",
              details: %{components: components}
            }} =
             Jido.Flow.new(%{
               name: "dependency_cycle",
               components: [
                 %{kind: :step, name: "one", action: Add, needs: ["two"]},
                 %{kind: :step, name: "two", action: Add, needs: ["one"]}
               ],
               output: Ref.result("one")
             })

    assert Enum.sort(components) == ["one", "two"]
  end

  test "call values reject invalid paths inside nested params" do
    for attrs <- component_attrs(),
        ref <- [Ref.input(:value), Ref.context(:value), Ref.result("load", :value)] do
      assert {:ok, _component} = Definition.component(put_params(attrs, %{nested: [ref]}))

      for path <- [[nil], [:value, nil, "key"], [:value, nil], [:value | :tail], [%{}]] do
        params = %{nested: [%{value: %{ref | path: path}}]}

        assert {:error,
                %InvalidDefinitionError{
                  message: "flow expression contains an invalid reference path",
                  details: %{path: error_path}
                }} = Definition.component(put_params(attrs, params))

        assert Enum.take(error_path, -4) == [:params, :nested, 0, :value]
      end
    end
  end

  test "component expression errors start with their field" do
    bad = %{nested: [Ref.input([nil])]}
    bad_condition = Jido.Expr.new!(:==, [Ref.input([nil]), 1])

    cases = [
      {:collection, %{kind: :map, name: "map", collection: bad, action: Add}},
      {:collection, %{kind: :reduce, name: "reduce", collection: bad, initial: %{}, action: Add}},
      {:initial, %{kind: :reduce, name: "reduce", collection: [], initial: bad, action: Add}},
      {:initial, iterate(%{initial: bad, update: %{}}, Jido.Expr.new!(:==, [true, true]))},
      {:update, iterate(%{initial: %{}, update: bad}, Jido.Expr.new!(:==, [true, true]))},
      {:condition, choice(%{name: "option", condition: bad_condition, action: Add})},
      {:completion, iterate(%{initial: %{}, update: %{}}, bad_condition)}
    ]

    for {field, attrs} <- cases do
      assert {:error, %InvalidDefinitionError{details: %{path: path}}} =
               Definition.component(attrs)

      assert field in path
    end
  end

  test "local values reject invalid paths in their valid scopes" do
    for path <- [[nil], [:value, nil], [:value | :tail], [-1]] do
      for ref <- [Ref.item(path), Ref.accumulator(path)] do
        assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
                 Definition.component(%{
                   kind: :reduce,
                   name: "reduce",
                   collection: [],
                   initial: %{},
                   action: Add,
                   params: %{nested: [ref]}
                 })
      end

      assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
               Definition.component(%{
                 kind: :map,
                 name: "map",
                 collection: [],
                 action: Add,
                 params: %{nested: [Ref.item(path)]}
               })

      for ref <- [Ref.state(path), Ref.body_result(path)] do
        assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
                 Definition.component(iterate(%{initial: %{}, update: %{nested: [ref]}}, true))
      end
    end
  end

  test "conditions and expression operands reject invalid paths" do
    for path <- [[nil], [:value | :tail]] do
      ref = Ref.input(path)

      assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
               Definition.component(%{
                 kind: :step,
                 name: "step",
                 action: Add,
                 params: %{value: Jido.Expr.new!(:+, [ref, 1])}
               })

      assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
               Jido.Flow.Value.condition(%Jido.Expr{operator: :==, operands: [ref, 1]}, :any)

      assert {:error, %InvalidDefinitionError{details: %{segment: _}}} =
               Definition.component(
                 choice(%{
                   name: "option",
                   condition: %Jido.Expr{operator: :==, operands: [ref, 1]},
                   action: Add
                 })
               )
    end
  end

  defp component_attrs do
    [
      %{kind: :step, name: "step", action: Add},
      %{kind: :subflow, name: "subflow", flow: NestedFlow},
      choice(%{name: "yes", condition: true, action: Add}),
      %{kind: :map, name: "map", collection: [], action: Add},
      %{kind: :reduce, name: "reduce", collection: [], initial: %{}, action: Add},
      iterate(%{initial: %{}, update: %{}}, true),
      %{kind: :invoke, name: "invoke", decision: Add, expander: Add}
    ]
  end

  defp choice(option) do
    %{kind: :choice, name: "route", options: [option], fallback: %{action: Add}}
  end

  defp iterate(state, completion) do
    %{
      kind: :iterate,
      name: "iterate",
      action: Add,
      state: state,
      completion: completion,
      max_iterations: 1
    }
  end

  defp put_params(%{kind: :choice} = attrs, params) do
    put_in(attrs, [:options, Access.at(0), :params], params)
  end

  defp put_params(attrs, params), do: Map.put(attrs, :params, params)
end
