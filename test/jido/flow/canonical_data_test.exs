defmodule JidoActionTest.Flow.CanonicalDataTest do
  use ExUnit.Case, async: true

  alias Jido.Flow
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.Add
  alias JidoActionTest.Fixtures.NestedFlow

  test "constructs the canonical Flow data" do
    load = %{
      kind: :step,
      name: "load",
      action: Add,
      params: %{value: Ref.input(:value), amount: 1},
      needs: [],
      meta: %{label: "Load"}
    }

    save = %{
      kind: :step,
      name: "save",
      action: Add,
      params: %{value: Ref.result("load", :value), amount: 1},
      needs: ["audit"],
      meta: %{}
    }

    audit = %{
      kind: :step,
      name: "audit",
      action: Add,
      params: %{value: Ref.input(:value), amount: 0},
      needs: [],
      meta: %{}
    }

    assert {:ok,
            %Flow{
              name: "canonical",
              components: %{
                "load" => %{
                  kind: :call,
                  call: %{kind: :action, target: Add, params: load_params},
                  meta: %{label: "Load"}
                },
                "save" => %{
                  kind: :call,
                  call: %{kind: :action, target: Add, params: save_params},
                  needs: ["audit"]
                },
                "audit" => %{
                  kind: :call,
                  call: %{kind: :action, target: Add, params: audit_params}
                }
              },
              output: %Ref{source: :result, component: "save", path: []}
            } = flow} =
             Flow.new(%{
               name: "canonical",
               components: [load, save, audit],
               output: Ref.result("save")
             })

    assert load_params == load.params
    assert save_params == save.params
    assert audit_params == audit.params

    assert {:ok,
            %{
              "load" => %{needs: [], references: [], effective: []},
              "save" => %{
                needs: ["audit"],
                references: ["load"],
                effective: ["audit", "load"]
              },
              "audit" => %{needs: [], references: [], effective: []}
            }} = Flow.dependencies(flow)
  end

  test "canonical validation rejects malformed call fields and runtime values" do
    flow = step_flow()
    node = flow.components["step"]
    template = node.call

    for {field, value} <- [
          kind: :worker,
          target: "Elixir.InvalidAction",
          params: self(),
          context: %{bound: true},
          metadata: %{source: "canonical"},
          metadata: [:not_a_map]
        ] do
      invalid_template = Map.put(template, field, value)
      invalid = put_in(flow.components["step"].call, invalid_template)
      assert_invalid_canonical(invalid)
    end
  end

  test "canonical validation requires an exact call record" do
    flow = step_flow()
    %{params: params} = template = flow.components["step"].call

    for call <- [
          {%{kind: :action, target: Add}, params},
          {template},
          {template, params, :extra},
          [template, params]
        ] do
      invalid = put_in(flow.components["step"].call, call)
      assert_invalid_canonical(invalid)
    end
  end

  test "canonical validation rejects unknown fields on every node kind" do
    flow =
      Flow.new!(%{
        name: "canonical_node_keys",
        components: [
          %{kind: :step, name: "step", action: Add},
          %{kind: :subflow, name: "subflow", flow: NestedFlow},
          %{
            kind: :choice,
            name: "choice",
            options: [%{name: "yes", condition: true, action: Add}],
            fallback: %{action: Add}
          },
          %{kind: :map, name: "map", collection: [], action: Add},
          %{kind: :reduce, name: "reduce", collection: [], initial: %{}, action: Add},
          %{
            kind: :iterate,
            name: "iterate",
            action: Add,
            state: %{initial: %{}, update: %{}},
            completion: true,
            max_iterations: 1
          }
        ],
        output: Ref.result("step")
      })

    for name <- Map.keys(flow.components) do
      invalid = put_in(flow.components[name], Map.put(flow.components[name], :extra, true))
      assert_invalid_canonical(invalid)
    end

    choice = flow.components["choice"]
    [option] = choice.options

    invalid_option =
      put_in(flow.components["choice"].options, [Map.put(option, :extra, true)])

    assert_invalid_canonical(invalid_option)

    invalid_state =
      put_in(
        flow.components["iterate"].state,
        Map.put(flow.components["iterate"].state, :extra, true)
      )

    assert_invalid_canonical(invalid_state)
  end

  test "canonical Invoke requires an exact target-only expander" do
    flow =
      Flow.new!(%{
        name: "canonical_invoke",
        components: [
          %{
            kind: :invoke,
            name: "invoke",
            decision: Add,
            expander: Add,
            params: %{value: 1, amount: 1}
          }
        ],
        output: Ref.result("invoke")
      })

    assert Flow.validate(flow) == {:ok, flow}

    expander = flow.components["invoke"].expander

    invalid =
      put_in(flow.components["invoke"].expander, Map.put(expander, :params, %{bound: true}))

    assert_invalid_canonical(invalid)

    invalid =
      put_in(flow.components["invoke"], Map.put(flow.components["invoke"], :extra, true))

    assert_invalid_canonical(invalid)
  end

  test "canonical validation preserves valid artifacts and rejects value normalization" do
    flow = step_flow()

    assert Flow.validate(flow) == {:ok, flow}
    assert Jido.Exec.Compiler.validate(flow) == {:ok, flow}

    invalid_params = put_in(flow.components["step"].call, replace_params(flow, Ref.item()))
    assert_invalid_canonical(invalid_params)

    assert_invalid_canonical(%{flow | output: Ref.item()})

    non_canonical_ref = %{flow.output | component: :step}

    assert {:error,
            %InvalidDefinitionError{
              message: "flow expression contains an invalid reference",
              details: %{path: [:output], ref_type: :result}
            }} = Flow.validate(%{flow | output: non_canonical_ref})
  end

  test "canonical Iterate state errors use the state field path" do
    flow =
      Flow.new!(%{
        name: "canonical_state_paths",
        components: [
          %{
            kind: :iterate,
            name: "loop",
            action: Add,
            state: %{schema: Zoi.map(), initial: %{}, update: %{}},
            completion: true,
            max_iterations: 1
          }
        ],
        output: Ref.result("loop")
      })

    state = flow.components["loop"].state

    for {invalid_state, expected_path} <- [
          {Map.put(state, :extra, true), [:components, "loop", :state, :extra]},
          {Map.delete(state, :update), [:components, "loop", :state, :update]},
          {:invalid, [:components, "loop", :state]},
          {%{state | schema: :invalid}, [:components, "loop", :state, :schema]},
          {%{state | initial: Ref.item()}, [:components, "loop", :state, :initial]}
        ] do
      invalid = put_in(flow.components["loop"].state, invalid_state)

      assert {:error, %InvalidDefinitionError{details: %{path: ^expected_path}}} =
               Flow.validate(invalid)
    end
  end

  defp step_flow do
    Flow.new!(%{
      name: "canonical_step",
      components: [%{kind: :step, name: "step", action: Add}],
      output: Ref.result("step")
    })
  end

  defp replace_params(flow, params) do
    template = flow.components["step"].call
    Map.put(template, :params, params)
  end

  defp assert_invalid_canonical(flow) do
    for validate <- [&Flow.validate/1, &Jido.Exec.Compiler.validate/1] do
      assert {:error, %InvalidDefinitionError{}} = validate.(flow)
    end
  end

  test "needs order does not change Flow identity" do
    flows =
      for needs <- [["a", "b"], ["b", "a"]] do
        Jido.Flow.new!(%{
          name: "needs_order",
          components: [
            %{kind: :step, name: "a", action: JidoActionTest.Fixtures.Actions.EchoParamsAction},
            %{kind: :step, name: "b", action: JidoActionTest.Fixtures.Actions.EchoParamsAction},
            %{
              kind: :step,
              name: "c",
              action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
              needs: needs
            }
          ],
          output: Jido.Flow.Ref.result("c")
        })
      end

    assert [ordered, reversed] = flows
    assert reversed.components["c"].needs == ["b", "a"]
    assert Jido.Flow.semantic_identity(ordered) == Jido.Flow.semantic_identity(reversed)

    assert Jido.Exec.compile!(ordered) |> Runic.Workflow.get_component("c") |> Map.get(:id) ==
             Jido.Exec.compile!(reversed) |> Runic.Workflow.get_component("c") |> Map.get(:id)
  end

  test "to_map and explain keep references distinct from literal maps" do
    flows =
      for output <- [
            %{value: Jido.Flow.Ref.input(:x)},
            %{value: %{source: :input, component: nil, path: [:x]}}
          ] do
        Jido.Flow.new!(%{
          name: "ref_or_literal",
          components: [
            %{kind: :step, name: "echo", action: JidoActionTest.Fixtures.Actions.EchoParamsAction}
          ],
          output: output
        })
      end

    [ref_flow, literal_flow] = flows
    assert %{output: %{value: %Jido.Flow.Ref{}}} = Jido.Flow.to_map(ref_flow)
    assert Jido.Flow.to_map(ref_flow) != Jido.Flow.to_map(literal_flow)
    assert {:ok, ref_explain} = Jido.Flow.explain(ref_flow)
    assert {:ok, literal_explain} = Jido.Flow.explain(literal_flow)
    assert ref_explain.output != literal_explain.output
  end
end
