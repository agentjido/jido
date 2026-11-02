defmodule Jido.Flow.CanonicalAuthoringTest.SparkFlow do
  @moduledoc false
  use Jido.Flow, name: "canonical_spark_flow"

  flow do
    step("add",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: value(1)},
      needs: [],
      meta: %{owner: "spark"}
    )

    output(result("add"))
  end
end

defmodule Jido.Flow.CanonicalAuthoringTest.SparkSubflow do
  @moduledoc false
  use Jido.Flow, name: "canonical_spark_subflow"

  flow do
    step("child",
      action: JidoActionTest.Fixtures.NestedFlow,
      params: %{value: input(:value)},
      meta: %{owner: "spark"}
    )

    output(result("child"))
  end
end

defmodule Jido.Flow.CanonicalAuthoringTest.SparkInvokeFlow do
  @moduledoc false
  use Jido.Flow, name: "canonical_invoke_flow"

  flow do
    invoke "next",
      decision: JidoActionTest.Fixtures.Actions.Add,
      expander: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1},
      meta: %{owner: "spark"}

    output(result("next"))
  end
end

defmodule Jido.Flow.CanonicalAuthoringTest.SparkMixedFlow do
  @moduledoc false
  use Jido.Flow, name: "canonical_mixed_flow", description: "All canonical authoring forms"
  alias JidoActionTest.Fixtures.Actions.Multiply

  flow do
    step("load",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1},
      meta: %{owner: "parity"}
    )

    step("child",
      action: JidoActionTest.Fixtures.NestedFlow,
      params: %{value: result("load", :value)},
      needs: ["load"]
    )

    choice("route") do
      option("add",
        condition: input(:kind) == :add,
        action: JidoActionTest.Fixtures.Actions.Add,
        params: %{value: result("child", :value), amount: 1}
      )

      otherwise(action: Multiply, params: %{value: result("child", :value), amount: 2})
    end

    map("mapped",
      collection: input(:items),
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: item(:value), amount: 1},
      on_error: :collect_errors
    )

    reduce("reduced",
      collection: result("mapped"),
      initial: %{value: 1},
      action: JidoActionTest.Fixtures.Actions.Multiply,
      params: %{value: accumulator(:value), amount: item(:value)}
    )

    iterate("loop") do
      state(Zoi.map(), initial: %{count: 0})
      action(JidoActionTest.Fixtures.Actions.Add)
      params(%{value: state(:count), amount: 1})
      update(%{count: body_result(:value)})
      repeat(2)
    end

    output(result("loop"))
  end
end

defmodule Jido.Flow.CanonicalAuthoringTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I7"
  alias Jido.Flow
  alias Jido.Flow.Codec
  alias JidoActionTest.FlowCodec, as: Codec
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.CodecRegistry
  alias JidoActionTest.Fixtures.FlowAuthoring
  alias JidoActionTest.Fixtures.InlineAuthoring
  alias JidoActionTest.Fixtures.InlineParityFlow
  alias JidoActionTest.Fixtures.NestedFlow
  alias JidoActionTest.Fixtures.Actions.Add

  test "all inline binding forms have equal DSL, direct, and JSON graphs and results" do
    direct = InlineAuthoring.direct_flow!()
    assert {:ok, built} = JidoActionTest.FlowBuilder.new(InlineAuthoring.data())
    dsl = InlineParityFlow.flow()
    assert built == direct
    assert dsl == direct
    registry = InlineAuthoring.registry()
    assert {:ok, document} = Codec.encode(built, registry)

    assert Enum.map(document["components"], & &1["call"]["target"]) == [
             %{"id" => "actions/demo/empty/v1", "vsn" => 1},
             %{"id" => "actions/demo/named/v1", "vsn" => 1},
             %{"id" => "actions/demo/multiple/v1", "vsn" => 1},
             %{"id" => "actions/demo/sole-map/v1", "vsn" => 1}
           ]

    assert {:ok, decoded} =
             document |> Jason.encode!() |> Jason.decode!() |> Codec.decode(registry)

    assert decoded == direct

    input = %{
      raw_name: " Ada ",
      payload: %{"profile" => %{"city" => "London"}, "active" => true, "extra" => "preserved"}
    }

    expected = %{
      "empty" => %{ready: true},
      "greeting" => %{message: "Welcome, Ada!"},
      "profile" => %{city: "London"}
    }

    for flow <- [dsl, built, direct, decoded] do
      assert Jido.Exec.run(flow, input, %{prefix: "Welcome"}) == {:ok, expected}
    end
  end

  test "looked-up Actions use only the new map authoring refs, dependencies, and metadata" do
    action = InlineParityFlow.step_action(:multiple)

    assert {:ok, flow} =
             JidoActionTest.FlowBuilder.new(%{
               output: Jido.Flow.Ref.result("message"),
               components: [
                 %{
                   kind: :step,
                   name: "gate",
                   action: InlineParityFlow.step_action(:empty),
                   params: %{}
                 },
                 %{
                   kind: :step,
                   name: "message",
                   action: action,
                   params: %{
                     name: Jido.Flow.Ref.input(:recipient),
                     prefix: Jido.Flow.Ref.input(:salutation)
                   },
                   needs: ["gate"],
                   meta: %{owner: "data"}
                 }
               ],
               name: "reused_inline"
             })

    assert %{
             call: %{
               kind: :action,
               target: ^action,
               params: %{name: %Ref{source: :input}, prefix: %Ref{source: :input}} = params
             },
             needs: ["gate"],
             meta: %{owner: "data"}
           } = flow.components["message"]

    assert params == %{name: Ref.input(:recipient), prefix: Ref.input(:salutation)}

    assert {:ok, %{"message" => %{needs: ["gate"], references: [], effective: ["gate"]}}} =
             Flow.dependencies(flow)

    assert Jido.Exec.run(flow, %{recipient: "Grace", salutation: "Hi"}) ==
             {:ok, %{message: "Hi, Grace!"}}
  end

  test "a normal Map can reuse a looked-up inline Action with item refs" do
    action = InlineParityFlow.step_action("named")

    assert {:ok, flow} =
             JidoActionTest.FlowBuilder.new(%{
               output: %{names: Jido.Flow.Ref.result("names")},
               components: [
                 %{
                   kind: :map,
                   name: "names",
                   collection: Jido.Flow.Ref.input(:people),
                   action: action,
                   params: %{name: Jido.Flow.Ref.item()}
                 }
               ],
               name: "mapped_inline"
             })

    assert %{
             kind: :map,
             call: %{kind: :action, target: ^action, params: %{name: %Ref{source: :item}}}
           } = flow.components["names"]

    assert Jido.Exec.run(flow, %{people: [" Ada ", " Grace "]}) ==
             {:ok, %{names: [%{name: "Ada"}, %{name: "Grace"}]}}
  end

  test "direct, and Spark Step authoring produce the same canonical data" do
    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "canonical_spark_flow",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "add",
            action: Add,
            params: %{value: Ref.input(:value), amount: 1},
            needs: [],
            meta: %{owner: "spark"}
          )
        ],
        output: Ref.result("add")
      )

    {:ok, built} =
      JidoActionTest.FlowBuilder.new(%{
        output: Jido.Flow.Ref.result("add"),
        components: [
          %{
            kind: :step,
            name: "add",
            action: Add,
            params: %{value: Jido.Flow.Ref.input(:value), amount: 1},
            needs: [],
            meta: %{owner: "spark"}
          }
        ],
        name: "canonical_spark_flow"
      })

    assert built == direct
    assert Jido.Flow.CanonicalAuthoringTest.SparkFlow.flow() == direct
  end

  test "Spark derives a Subflow and map authoring declares its kind" do
    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "canonical_spark_subflow",
        components: [
          JidoActionTest.FlowComponent.subflow!(
            name: "child",
            flow: NestedFlow,
            params: %{value: Ref.input(:value)},
            needs: [],
            meta: %{owner: "spark"}
          )
        ],
        output: Ref.result("child")
      )

    {:ok, built} =
      JidoActionTest.FlowBuilder.new(%{
        output: Jido.Flow.Ref.result("child"),
        components: [
          %{
            kind: :subflow,
            flow: NestedFlow,
            name: "child",
            params: %{value: Jido.Flow.Ref.input(:value)},
            meta: %{owner: "spark"}
          }
        ],
        name: "canonical_spark_subflow"
      })

    assert built == direct
    assert Jido.Flow.CanonicalAuthoringTest.SparkSubflow.flow() == direct

    assert %{kind: :call, call: %{kind: :flow, target: NestedFlow, params: _params}} =
             built.components["child"]
  end

  test "direct, Spark, and JSON Invoke forms produce the same canonical data" do
    direct =
      JidoActionTest.FlowBuilder.new!(
        name: "canonical_invoke_flow",
        components: [
          JidoActionTest.FlowComponent.invoke!(
            name: "next",
            decision: Add,
            expander: Add,
            params: %{value: Ref.input(:value), amount: 1},
            meta: %{owner: "spark"}
          )
        ],
        output: Ref.result("next")
      )

    {:ok, built} =
      JidoActionTest.FlowBuilder.new(%{
        output: Jido.Flow.Ref.result("next"),
        components: [
          %{
            kind: :invoke,
            name: "next",
            decision: Add,
            expander: Add,
            params: %{value: Jido.Flow.Ref.input(:value), amount: 1},
            meta: %{owner: "spark"}
          }
        ],
        name: "canonical_invoke_flow"
      })

    assert built == direct
    assert Jido.Flow.CanonicalAuthoringTest.SparkInvokeFlow.flow() == direct
    assert {:ok, document, registry} = Codec.encode(direct)
    assert [%{"kind" => "invoke"} = encoded] = document["components"]
    refute Map.has_key?(encoded, "max_continuations")
    assert Codec.decode(document, registry) == {:ok, direct}
  end

  test "Invoke and Handoff expose every target call and bound value" do
    add = Add
    invoke_params = %{value: Ref.input(:value), amount: 1}

    assert {:ok, {"next", invoke}} =
             Jido.Flow.Definition.component(%{
               kind: :invoke,
               name: "next",
               decision: Add,
               expander: Add,
               params: invoke_params
             })

    assert [
             {:decision, %{kind: :action, target: ^add, params: ^invoke_params}, ^invoke_params},
             {:expander, %{kind: :action, target: ^add}, nil}
           ] = Jido.Flow.Definition.calls(invoke)

    assert Jido.Flow.Definition.values(invoke) == [invoke_params]

    handoff_params = %{value: Ref.input(:value)}

    assert {:ok, {"handoff", handoff}} =
             Jido.Flow.Definition.component(%{
               kind: :handoff,
               name: "handoff",
               selector: Add,
               params: handoff_params
             })

    assert [
             {:selector, %{kind: :action, target: ^add, params: ^handoff_params}, ^handoff_params}
           ] = Jido.Flow.Definition.calls(handoff)

    assert Jido.Flow.Definition.values(handoff) == [handoff_params]
  end

  test "runtime DSL lowering preserves Invoke and Handoff declarations" do
    invoke_module =
      Module.concat(__MODULE__, "RuntimeInvoke#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(invoke_module)} do
      use Jido.Flow, name: "runtime_invoke"

      flow do
        invoke "next",
          decision: #{inspect(Add)},
          expander: #{inspect(Add)},
          params: %{value: input(:value), amount: 1}

        output result("next")
      end
    end
    """)

    assert %{
             kind: :invoke,
             decision: %{target: Add, params: %{value: %Ref{source: :input}, amount: 1}},
             expander: %{target: Add}
           } = apply(invoke_module, :flow, []).components["next"]

    handoff_module =
      Module.concat(__MODULE__, "RuntimeHandoff#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(handoff_module)} do
      use Jido.Flow, name: "runtime_handoff"

      flow do
        handoff "next", selector: #{inspect(Add)}, params: %{value: input(:value)}
        output result("next")
      end
    end
    """)

    assert %{
             kind: :handoff,
             selector: %{target: Add, params: %{value: %Ref{source: :input}}}
           } = apply(handoff_module, :flow, []).components["next"]
  end

  test "direct, Spark, and JSON authoring produce one mixed canonical Flow" do
    direct = FlowAuthoring.mixed_flow!()
    assert {:ok, built} = JidoActionTest.FlowBuilder.new(FlowAuthoring.mixed_data())
    assert Jido.Flow.CanonicalAuthoringTest.SparkMixedFlow.flow() == direct
    assert built == direct
    registry = CodecRegistry.mixed()
    assert {:ok, document} = Codec.encode(direct, registry)
    json = Jason.encode!(document)
    assert {:ok, decoded} = json |> Jason.decode!() |> Codec.decode(registry)
    assert decoded == direct

    assert direct.components["load"].kind == :call
    assert direct.components["load"].call.kind == :action
    assert direct.components["child"].kind == :call
    assert direct.components["child"].call.kind == :flow

    assert Enum.map(["route", "mapped", "reduced", "loop"], fn name ->
             direct.components[name].kind
           end) == [:choice, :map, :reduce, :iterate]

    compiled_forms =
      for flow <- [direct, built, decoded, Jido.Flow.CanonicalAuthoringTest.SparkMixedFlow.flow()] do
        assert {:ok, compiled} = Jido.Exec.compile(flow)
        Runic.Workflow.build_log(compiled)
      end

    assert length(Enum.uniq(compiled_forms)) == 1
  end

  test "Spark source data stays outside the canonical Flow" do
    flow = Jido.Flow.CanonicalAuthoringTest.SparkFlow.flow()
    source_map = Jido.Flow.CanonicalAuthoringTest.SparkFlow.__jido_flow_source_map__()
    assert flow.components["add"].meta == %{owner: "spark"}
    refute Map.has_key?(flow.components["add"].meta, :line)
    assert %{file: file, line: line} = source_map[[:components, "add"]]
    assert is_binary(file)
    assert is_integer(line)
    assert %{file: ^file} = source_map[[:output]]
  end

  test "map authoring rejects removed aliases" do
    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(%{
               output: Jido.Flow.Ref.result("add"),
               components: [
                 %{kind: :step, name: "add", action: Add, params: %{}, deps: ["other"]}
               ],
               name: "bad_data"
             })

    assert Exception.message(error) == "unknown Flow field: :deps"
  end

  test "map authoring accepts needs for every component kind" do
    option = %{name: "yes", condition: true, action: Add, params: %{}}
    fallback = %{action: Add, params: %{}}

    assert {:ok, flow} =
             JidoActionTest.FlowBuilder.new(%{
               output: Jido.Flow.Ref.result("invoke"),
               components: [
                 %{kind: :step, name: "root", action: Add, params: %{}},
                 %{kind: :step, name: "action", action: Add, params: %{}, needs: ["root"]},
                 %{
                   kind: :subflow,
                   flow: NestedFlow,
                   name: "subflow",
                   params: %{},
                   needs: ["root"]
                 },
                 %{
                   kind: :choice,
                   name: "choice",
                   options: [option],
                   fallback: fallback,
                   needs: ["root"]
                 },
                 %{
                   kind: :map,
                   name: "map",
                   collection: [],
                   action: Add,
                   params: %{},
                   needs: ["root"]
                 },
                 %{
                   kind: :reduce,
                   name: "reduce",
                   collection: [],
                   initial: %{},
                   action: Add,
                   params: %{},
                   needs: ["root"]
                 },
                 %{
                   kind: :iterate,
                   name: "iterate",
                   action: Add,
                   params: %{},
                   state: %{schema: Zoi.map(), initial: %{}, update: %{}},
                   needs: ["root"],
                   completion: true,
                   max_iterations: 1
                 },
                 %{
                   kind: :invoke,
                   name: "invoke",
                   decision: Add,
                   expander: Add,
                   params: %{},
                   needs: ["action", "subflow", "choice", "map", "reduce", "iterate"]
                 }
               ],
               name: "all_data_needs"
             })

    assert Enum.map(
             ["root", "action", "subflow", "choice", "map", "reduce", "iterate", "invoke"],
             fn name -> {flow.components[name].kind, flow.components[name].needs} end
           ) == [
             {:call, []},
             {:call, ["root"]},
             {:call, ["root"]},
             {:choice, ["root"]},
             {:map, ["root"]},
             {:reduce, ["root"]},
             {:iterate, ["root"]},
             {:invoke, ["action", "subflow", "choice", "map", "reduce", "iterate"]}
           ]
  end

  test "map authoring rejects after for every component kind" do
    option = %{name: "yes", condition: true, action: Add, params: %{}}
    fallback = %{action: Add, params: %{}}
    state = [schema: Zoi.map(), initial: %{}, update: %{}]

    definitions = [
      %{
        components: [%{kind: :step, name: "step", action: Add, params: %{}, after: []}],
        name: "step_after"
      },
      %{
        components: [%{kind: :subflow, flow: NestedFlow, name: "subflow", params: %{}, after: []}],
        name: "subflow_after"
      },
      %{
        components: [
          %{kind: :choice, name: "choice", options: [option], fallback: fallback, after: []}
        ],
        name: "choice_after"
      },
      %{
        components: [
          %{kind: :map, name: "map", collection: [], action: Add, params: %{}, after: []}
        ],
        name: "map_after"
      },
      %{
        components: [
          %{
            kind: :reduce,
            name: "reduce",
            collection: [],
            initial: %{},
            action: Add,
            params: %{},
            after: []
          }
        ],
        name: "reduce_after"
      },
      %{
        components: [
          %{kind: :iterate, name: "iterate", action: Add, params: %{}, state: state, after: []}
        ],
        name: "iterate_after"
      },
      %{
        components: [
          %{
            kind: :invoke,
            name: "invoke",
            decision: Add,
            expander: Add,
            params: %{},
            after: []
          }
        ],
        name: "invoke_after"
      }
    ]

    for data <- definitions do
      assert {:error, error} = JidoActionTest.FlowBuilder.new(Map.put(data, :output, %{}))
      assert error.message =~ "unknown"
      assert error.message =~ ":after"
      assert error.details.path == [:components, 0, :after]
    end
  end

  test "map authoring still requires an explicit output" do
    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(%{
               components: [%{kind: :step, name: "step", action: Add, params: %{}}],
               name: "missing_output"
             })

    assert error.message == "Flow output is required"
    assert error.details.path == [:output]
  end

  test "public inspection exposes needs and sorted effective dependencies" do
    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "dependency_inspection",
        components: [
          JidoActionTest.FlowComponent.step!(name: "beta", action: Add),
          JidoActionTest.FlowComponent.step!(name: "alpha", action: Add),
          JidoActionTest.FlowComponent.step!(
            name: "work",
            action: Add,
            params: [Ref.result("beta"), Ref.result("alpha"), Ref.result("beta")],
            needs: ["beta", "alpha"]
          )
        ],
        output: Ref.result("work")
      )

    assert %{components: [_beta, _alpha, work]} = Flow.to_map(flow)
    assert work.needs == ["beta", "alpha"]
    refute Map.has_key?(work, :after)
    assert {:ok, dependencies} = Flow.dependencies(flow)

    assert dependencies["work"] == %{
             needs: ["beta", "alpha"],
             references: ["alpha", "beta"],
             effective: ["alpha", "beta"]
           }

    assert {:ok, %{version: 1, dependencies: ^dependencies}} = Flow.explain(flow)
  end

  test "canonical public operations accept one Flow and reject other subjects" do
    flow = FlowAuthoring.math_flow!()
    assert JidoActionTest.FlowBuilder.new(flow) == {:ok, flow}
    assert %Runic.Workflow{} = Jido.Exec.compile!(flow, source_map: %{})
    assert %{name: "math_flow", components: [_first, _second]} = Flow.to_map(flow)
    assert {:ok, %{"double" => %{references: ["add_one"]}}} = Flow.dependencies(flow)
    assert {:ok, %{kind: :flow, name: "math_flow"}} = Flow.explain(flow)
    assert {:ok, %{digest: digest, uuid: uuid}} = Flow.semantic_identity(flow)
    assert is_binary(digest)
    assert is_binary(uuid)
    assert {:ok, ^flow} = Flow.validate(flow)
    assert {:ok, ^flow} = Jido.Exec.Compiler.validate(flow)

    for operation <- [
          &Flow.dependencies/1,
          &Flow.explain/1,
          &Flow.semantic_identity/1,
          &Flow.validate/1,
          &Jido.Exec.Compiler.validate/1
        ] do
      assert {:error, error} = operation.(:not_a_flow)
      assert Exception.message(error) == "expected a Jido.Flow artifact"
    end

    invalid =
      JidoActionTest.FlowBuilder.new!(
        name: "compile_bang_error",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "missing",
            action: JidoActionTest.Fixtures.Actions.MissingRun
          )
        ],
        output: Ref.result("missing")
      )

    assert_raise Jido.Flow.Error.InvalidDefinitionError, fn -> Jido.Exec.compile!(invalid) end

    assert_raise Jido.Flow.Error.InvalidDefinitionError, fn ->
      JidoActionTest.FlowBuilder.new!(name: "missing_output")
    end
  end
end
