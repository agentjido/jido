defmodule Jido.Flow.ValidationTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I8"
  alias Jido.Expr
  alias Jido.Error
  alias Jido.Flow
  alias Jido.Catalog
  alias Jido.Flow.Ref
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.NestedFlow

  defmodule ProbeAction do
    use Jido.Action, name: "graph_probe"
    @impl true
    def run(_params, _context) do
      raise "validation must not run Action work"
    end
  end

  defp registry do
    Catalog.from_targets!(__MODULE__, :jido, %{
      {"action", 1} => {:action, ProbeAction},
      {"schema", 1} => {:schema, Jido.Joi.map()},
      {"flow", 1} => {:flow, NestedFlow}
    })
  end

  defp stored(components, output) do
    %{
      "type" => "jido.flow",
      "vsn" => 2,
      "name" => "graph",
      "description" => nil,
      "components" => components,
      "output" => output
    }
  end

  defp stored_step(name, needs) do
    %{
      "name" => name,
      "needs" => needs,
      "meta" => %{"$type" => "map", "entries" => []},
      "kind" => "call",
      "call" => %{
        "kind" => "action",
        "target" => %{"id" => "action", "vsn" => 1},
        "params" => %{"$type" => "map", "entries" => []}
      }
    }
  end

  defp stored_ref(name) do
    %{"$ref" => %{"source" => "result", "component" => name, "path" => []}}
  end

  defp step(name, needs) do
    JidoActionTest.FlowComponent.step!(name: name, action: ProbeAction, needs: needs)
  end

  test "direct, map, DSL, and stored graphs agree on valid and invalid dependencies" do
    cases = [
      {[{"one", []}, {"two", ["one"]}], "two", :ok},
      {[{"two", ["one"]}, {"one", []}], "two", :ok},
      {[{"one", []}, {"two", []}], "two", :ok},
      {[{"one", ["missing"]}], "one", :error},
      {[{"one", []}], "missing", :error},
      {[{"one", ["one"]}], "one", :error},
      {[{"one", ["two"]}, {"two", ["one"]}], "one", :error},
      {[{"one", []}, {"one", []}], "one", :error}
    ]

    for {{edges, output, expected}, index} <- Enum.with_index(cases) do
      components = Enum.map(edges, fn {name, needs} -> step(name, needs) end)

      direct =
        JidoActionTest.FlowBuilder.new(
          name: "graph",
          components: components,
          output: Ref.result(output)
        )

      built =
        JidoActionTest.FlowBuilder.new(%{
          output: Ref.result(output),
          components:
            Enum.map(
              edges,
              fn {name, needs} ->
                %{kind: :step, name: name, action: ProbeAction, params: %{}, needs: needs}
              end
            ),
          name: "graph"
        })

      document =
        stored(
          Enum.map(edges, fn {name, needs} -> stored_step(name, needs) end),
          stored_ref(output)
        )

      decoded = Codec.decode(document, registry())
      module = Module.concat(__MODULE__, "DependencyCase#{index}")

      declarations =
        Enum.map_join(edges, "\n", fn {name, needs} ->
          "step #{inspect(name)}, action: #{inspect(ProbeAction)}, params: %{}, needs: #{inspect(needs)}"
        end)

      source = "defmodule #{inspect(module)} do
  use Jido.Flow, name: \"graph\"
  flow do
    #{declarations}
    output(result(#{inspect(output)}))
  end
end
"

      case expected do
        :ok ->
          assert {:ok, flow} = direct
          assert {:ok, ^flow} = built
          assert {:ok, ^flow} = decoded
          Code.compile_string(source)
          assert module.flow() == flow
          assert {:ok, ^flow} = Flow.validate(flow)

        :error ->
          assert {:error, %Error.ValidationError{}} = direct
          assert {:error, %Error.ValidationError{}} = built
          assert {:error, %Error.ValidationError{}} = decoded
          assert_raise CompileError, fn -> Code.compile_string(source) end
      end
    end
  end

  test "data and Codec diagnostics use the same dependency order" do
    component = step("one", ["z_missing", "a_missing"])

    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(
               name: "graph",
               components: [component],
               output: Ref.result("one")
             )

    assert error.details == %{owner: "one", component: "z_missing", path: [:components, 0]}
    document = stored([stored_step("one", component.needs)], stored_ref("one"))
    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(document, registry())

    assert Enum.map(errors, & &1.details) == [
             %{owner: "one", component: "z_missing", path: ["components", 0]},
             %{owner: "one", component: "a_missing", path: ["components", 0]}
           ]

    assert {:error, first} = Codec.decode(document, registry())
    assert first.details == hd(errors).details
  end

  test "duplicates and missing references aggregate without cycle or Handoff cascades" do
    components = [stored_step("same", ["z_missing", "a_missing"]), stored_step("same", ["same"])]
    output = [stored_ref("out_z"), stored_ref("out_a"), stored_ref("out_z")]

    assert {:error, %Error.Invalid{errors: errors}} =
             Codec.diagnose(stored(components, output), registry())

    assert Enum.map(errors, & &1.details) == [
             %{name: "same", path: ["components", 1, "name"]},
             %{owner: :output, component: "out_z", path: ["output"]},
             %{owner: :output, component: "out_a", path: ["output"]},
             %{owner: "same", component: "z_missing", path: ["components", 0]},
             %{owner: "same", component: "a_missing", path: ["components", 0]}
           ]

    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(
               name: "graph",
               components: [step("same", ["missing"]), step("same", [])],
               output: Ref.result("missing_output")
             )

    assert error.details == %{name: "same", path: [:components, 1, :name]}
  end

  test "nil output retains canonical and stored graph error precedence" do
    components = [step("same", []), step("same", [])]

    assert {:error, %{message: "Flow output is required", details: %{path: [:output]}}} =
             JidoActionTest.FlowBuilder.new(name: "graph", components: components, output: nil)

    # Data and stored diagnostics report the required output first.
    assert {:error, %Error.Invalid{errors: [output, duplicate]}} =
             Codec.diagnose(
               stored([stored_step("same", []), stored_step("same", [])], nil),
               registry()
             )

    assert duplicate.message == "duplicate component name"
    assert output.message == "Flow output is required"

    assert {:error, %Error.Invalid{errors: [required]}} =
             Codec.diagnose(stored([stored_step("one", [])], nil), registry())

    assert required.message == "Flow output is required"
    assert required.details.path == ["output"]
  end

  test "all component expression fields contribute static dependencies" do
    ref = fn name -> Ref.result(name) end

    components = [
      JidoActionTest.FlowComponent.step!(
        name: "step",
        action: ProbeAction,
        params: ref.("dep_step")
      ),
      JidoActionTest.FlowComponent.subflow!(
        name: "child",
        flow: NestedFlow,
        params: ref.("dep_child")
      ),
      JidoActionTest.FlowComponent.choice!(
        name: "choice",
        options: [
          JidoActionTest.FlowComponent.option!(
            name: "yes",
            action: ProbeAction,
            condition: Expr.new!(:or, [true, Expr.new!(:==, [ref.("dep_condition"), 1])]),
            params: ref.("dep_option")
          )
        ],
        fallback: [action: ProbeAction, params: ref.("dep_fallback")]
      ),
      JidoActionTest.FlowComponent.map!(
        name: "mapped",
        action: ProbeAction,
        collection: ref.("dep_collection"),
        params: [Ref.item(), ref.("dep_map_params")]
      ),
      JidoActionTest.FlowComponent.reduce!(
        name: "reduced",
        action: ProbeAction,
        collection: ref.("dep_reduce_collection"),
        initial: ref.("dep_reduce_initial"),
        params: [Ref.accumulator(), ref.("dep_reduce_params")]
      ),
      JidoActionTest.FlowComponent.iterate!(
        name: "iterated",
        action: ProbeAction,
        params: [Ref.state(), ref.("dep_iterate_params")],
        state: [
          schema: Jido.Joi.map(),
          initial: ref.("dep_initial"),
          update: [Ref.body_result(), ref.("dep_update")]
        ],
        completion: Expr.new!(:==, [Ref.iteration_index(), ref.("dep_completion")]),
        max_iterations: 1
      )
    ]

    dependencies = [
      "dep_step",
      "dep_child",
      "dep_condition",
      "dep_option",
      "dep_fallback",
      "dep_collection",
      "dep_map_params",
      "dep_reduce_collection",
      "dep_reduce_initial",
      "dep_reduce_params",
      "dep_iterate_params",
      "dep_initial",
      "dep_update",
      "dep_completion"
    ]

    producers = Enum.map(dependencies, &step(&1, []))

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "graph",
        components: producers ++ components,
        output: %{}
      )

    assert {:ok, document} = Codec.encode(flow, registry())
    document = %{document | "components" => Enum.drop(document["components"], length(producers))}
    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(document, registry())
    assert Enum.sort(Enum.map(errors, & &1.details.component)) == Enum.sort(dependencies)
    assert Enum.all?(errors, &(&1.message == "Flow reference points to an unknown component"))

    assert {:error, %{details: %{component: "dep_step"}}} =
             Flow.validate(%{flow | components: Map.drop(flow.components, dependencies)})
  end

  test "Handoff checks use graph sinks and the complete result" do
    handoff =
      JidoActionTest.FlowComponent.handoff!(
        name: "next",
        selector: ProbeAction
      )

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "graph",
        components: [handoff],
        output: Ref.result("next")
      )

    assert {:ok, document} = Codec.encode(flow, registry())
    [stored_handoff] = document["components"]

    invalid = %{
      document
      | "components" => [stored_handoff, stored_step("independent", [])],
        "output" => [stored_ref("next")]
    }

    assert {:error, %Error.Invalid{errors: errors}} = Codec.diagnose(invalid, registry())

    assert Enum.map(errors, &{&1.message, &1.details.path}) == [
             {"Handoff must be the final component in the Flow", ["components", 0]},
             {"Flow output must be the complete Handoff result", ["output"]}
           ]

    assert {:error,
            %{
              message: "Handoff must be the final component in the Flow",
              details: %{
                component: "next",
                handoff: "next",
                terminal_components: ["independent", "next"],
                path: [:components, 0]
              }
            }} =
             JidoActionTest.FlowBuilder.new(
               name: "graph",
               components: [handoff, step("independent", [])],
               output: [Ref.result("next")]
             )

    assert {:error, %Error.Invalid{errors: [multiple]}} =
             Codec.diagnose(
               %{
                 document
                 | "components" => [stored_handoff, %{stored_handoff | "name" => "second"}]
               },
               registry()
             )

    assert multiple.message == "Flow can contain only one Handoff component"

    assert multiple.details == %{
             component: "second",
             components: ["next", "second"],
             path: ["components", 1]
           }

    handoff_after_other =
      JidoActionTest.FlowComponent.handoff!(
        name: "next",
        selector: ProbeAction,
        needs: ["other"]
      )

    invalid_outputs = [
      {[handoff], Ref.input(:value)},
      {[step("other", []), handoff_after_other], Ref.result("other")},
      {[handoff], Ref.result("next", :value)}
    ]

    for {components, output} <- invalid_outputs do
      assert {:error,
              %{
                message: "Flow output must be the complete Handoff result",
                details: %{handoff: "next", path: [:output]}
              }} =
               JidoActionTest.FlowBuilder.new(
                 name: "graph",
                 components: components,
                 output: output
               )
    end

    assert {:error, %{message: "Handoff must be the final component in the Flow"}} =
             JidoActionTest.FlowBuilder.new(%{
               output: [Ref.result("next")],
               components: [
                 %{
                   kind: :handoff,
                   name: "next",
                   selector: ProbeAction,
                   params: %{}
                 },
                 %{kind: :step, name: "independent", action: ProbeAction, params: %{}}
               ],
               name: "graph"
             })

    source = "defmodule Jido.Flow.ValidationTest.NonterminalHandoff do
  use Jido.Flow, name: \"graph\"
  flow do
    handoff \"next\", selector: #{inspect(ProbeAction)}, params: %{}
    step \"independent\", action: #{inspect(ProbeAction)}, params: %{}
    output([result(\"next\")])
  end
end
"

    error =
      assert_raise CompileError, ~r/Handoff must be the final component/, fn ->
        Code.compile_string(source, "nonterminal_handoff.ex")
      end

    assert error.file == "nonterminal_handoff.ex"
    assert error.line == 4
  end

  test "Handoff parameter references precede terminal graph rules" do
    handoff =
      JidoActionTest.FlowComponent.handoff!(
        name: "next",
        selector: ProbeAction,
        params: Expr.new!(:and, [false, Ref.result("missing")])
      )

    assert {:error, error} =
             JidoActionTest.FlowBuilder.new(name: "graph", components: [handoff], output: %{})

    assert error.details == %{owner: "next", component: "missing", path: [:components, 0]}

    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "graph",
        components: [step("missing", []), handoff],
        output: Ref.result("next")
      )

    assert {:ok, document} = Codec.encode(flow, registry())

    assert {:error, %Error.Invalid{errors: [error]}} =
             Codec.diagnose(%{document | "components" => tl(document["components"])}, registry())

    assert error.details == %{owner: "next", component: "missing", path: ["components", 0]}
  end

  test "missing references and cycles identify their source declaration" do
    cases = [
      {"missing_component", ~s|step "one", action: #{inspect(ProbeAction)}, params: %{}, needs: ["absent"]|,
       ~s|output(result("one"))|, 4},
      {"missing_output", ~s|step "one", action: #{inspect(ProbeAction)}, params: %{}|, ~s|output(result("absent"))|, 5},
      {"self_cycle", ~s|step "one", action: #{inspect(ProbeAction)}, params: %{}, needs: ["one"]|,
       ~s|output(result("one"))|, 4}
    ]

    for {name, declaration, output, line} <- cases do
      module = Module.concat(__MODULE__, name)
      source = "defmodule #{inspect(module)} do
use Jido.Flow, name: #{inspect(name)}
flow do
#{declaration}
#{output}
end
end"
      file = name <> ".ex"
      error = assert_raise CompileError, fn -> Code.compile_string(source, file) end
      assert error.file == file
      assert error.line == line
    end
  end

  test "a duplicate across component kinds points to the second occurrence" do
    source = "defmodule Jido.Flow.ValidationTest.CrossKindDuplicate do
  use Jido.Flow, name: \"cross_kind_duplicate\"
  flow do
    step \"same\", action: #{inspect(ProbeAction)}, params: %{}
    map \"same\", collection: [], action: #{inspect(ProbeAction)}, params: %{}
    reduce \"same\", collection: [], initial: %{}, action: #{inspect(ProbeAction)}, params: %{}
    output(result(\"same\"))
  end
end
"

    error =
      assert_raise CompileError, ~r/duplicate component name/, fn ->
        Code.compile_string(source, "cross_kind_duplicate.ex")
      end

    assert error.file == "cross_kind_duplicate.ex"
    assert error.line == 5
  end

  test "cycle errors retain blocked nodes and point to the first authored blocked component" do
    edges = [{"blocked", ["one"]}, {"one", ["two"]}, {"two", ["one"]}]
    components = Enum.map(edges, fn {name, dependencies} -> step(name, dependencies) end)

    assert {:error, canonical} =
             JidoActionTest.FlowBuilder.new(
               name: "blocked_cycle",
               components: components,
               output: Ref.result("blocked")
             )

    assert canonical.message == "flow dependency graph contains a cycle"
    assert Enum.sort(canonical.details.components) == ["blocked", "one", "two"]

    document =
      stored(
        Enum.map(edges, fn {name, dependencies} -> stored_step(name, dependencies) end),
        stored_ref("blocked")
      )

    assert {:error, %Error.Invalid{errors: [stored_error]}} = Codec.diagnose(document, registry())
    assert stored_error.details == Map.put(canonical.details, :path, ["components"])
    source = "defmodule Jido.Flow.ValidationTest.BlockedCycle do
  use Jido.Flow, name: \"blocked_cycle\"
  flow do
    step \"blocked\", action: #{inspect(ProbeAction)}, params: %{}, needs: [\"one\"]
    step \"one\", action: #{inspect(ProbeAction)}, params: %{}, needs: [\"two\"]
    step \"two\", action: #{inspect(ProbeAction)}, params: %{}, needs: [\"one\"]
    output(result(\"blocked\"))
  end
end
"
    error = assert_raise CompileError, fn -> Code.compile_string(source, "blocked_cycle.ex") end
    assert error.file == "blocked_cycle.ex"
    assert error.line == 4
  end

  test "unloaded targets remain valid for inert construction and decoding" do
    component =
      JidoActionTest.FlowComponent.step!(
        name: "one",
        action: NotLoadedAction,
        params: Expr.new!(:+, [1, 2])
      )

    assert {:ok, flow} =
             JidoActionTest.FlowBuilder.new(
               name: "graph",
               components: [component],
               output: Ref.result("one")
             )

    assert {:ok, ^flow} = Flow.validate(flow)

    registry =
      Catalog.from_targets!(__MODULE__, :jido, %{
        {"unloaded", 1} => {:action, NotLoadedAction},
        {"schema", 1} => {:schema, Jido.Joi.map()}
      })

    assert {:ok, document} = Codec.encode(flow, registry)
    assert {:ok, ^flow} = Codec.diagnose(document, registry)
  end
end
