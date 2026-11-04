Code.require_file("../support/flows/components.ex", __DIR__)
Code.require_file("../support/flows/hostile.ex", __DIR__)

defmodule JidoActionTest.Authoring.RejectionsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.{Exec, Flow}
  alias Jido.Flow.{Graph, Ref}
  alias Jido.Test.Flow.Component, as: FlowComponent
  alias JidoActionTest.Authoring.Components
  alias JidoActionTest.Authoring.Hostile
  alias Jido.Test.Flow.AuthoringCompiler

  test "Action-only component slots reject a Flow target at executable validation" do
    child = Components.Child

    option =
      Jido.Test.Flow.Component.option!(name: "selected", condition: true, action: child)

    fallback = Jido.Test.Flow.Component.fallback!(action: Components.Echo)

    state =
      Components.IterateRepeat.flow().components |> Map.fetch!("counter") |> Map.fetch!(:state)

    components = [
      {Jido.Test.Flow.Component.map!(name: "node", collection: [], action: child), :action},
      {Jido.Test.Flow.Component.reduce!(
         name: "node",
         collection: [],
         initial: %{},
         action: child
       ), :action},
      {Jido.Test.Flow.Component.iterate!(
         name: "node",
         state: state,
         action: child,
         completion: true,
         max_iterations: 1
       ), :action},
      {Jido.Test.Flow.Component.choice!(name: "node", options: [option], fallback: fallback), "selected"},
      {Jido.Test.Flow.Component.choice!(
         name: "node",
         options: [
           Jido.Test.Flow.Component.option!(
             name: "selected",
             condition: true,
             action: Components.Echo
           )
         ],
         fallback: Jido.Test.Flow.Component.fallback!(action: child)
       ), :fallback},
      {Jido.Test.Flow.Component.invoke!(
         name: "node",
         decision: child,
         expander: Components.Expand
       ), :decision},
      {Jido.Test.Flow.Component.invoke!(
         name: "node",
         decision: Components.Decide,
         expander: child
       ), :expander}
    ]

    for {component, field} <- components do
      flow =
        Jido.Test.Flow.Builder.new!(
          name: "wrong_target",
          components: [component],
          output: Ref.result("node")
        )

      assert {:error, error} = Jido.Exec.Compiler.validate(flow)
      assert error.details.component == "node"
      assert error.details.field == field
      assert error.details.expected == :action
      assert error.details.actual == :flow
      assert {:error, _} = Exec.run(flow)
    end
  end

  test "Map, Reduce, and Iterate reject references outside each local scope" do
    assert {:error, map_error} =
             Jido.Test.Flow.Component.map(
               name: "map",
               collection: Ref.item(),
               action: Components.MapItem
             )

    assert map_error.details.ref_type == :item
    assert map_error.details.scope == :map_collection

    assert {:error, map_params_error} =
             Jido.Test.Flow.Component.map(
               name: "map",
               collection: [],
               action: Components.MapItem,
               params: %{value: Ref.accumulator()}
             )

    assert map_params_error.details.ref_type == :accumulator
    assert map_params_error.details.scope == :map_params

    assert {:error, reduce_error} =
             Jido.Test.Flow.Component.reduce(
               name: "reduce",
               collection: [],
               initial: Ref.accumulator(),
               action: Components.Fold
             )

    assert reduce_error.details.ref_type == :accumulator
    assert reduce_error.details.scope == :reduce_initial

    assert {:error, iterate_error} =
             Jido.Test.Flow.Component.state(initial: Ref.state(:count), update: %{})

    assert iterate_error.details.ref_type == :state
    assert iterate_error.details.scope == :iterate_initial
  end

  test "Reduce rejects an invalid initial value before running its body" do
    assert {:error, error} =
             Exec.run(
               Hostile.ReduceInitial,
               %{items: [1, 2], initial: :not_a_map},
               %{observer: self()}
             )

    assert error.message == "reduce initial value must be a map or Jido.Action.Output"
    assert error.phase == :reduce_initial
    assert error.details.node == "fold"
    refute_received {:fold, _, _}
  end

  test "Choice rejects missing fallback and non-Boolean direct conditions" do
    valid_option =
      Jido.Test.Flow.Component.option!(name: "ready", condition: true, action: Hostile.Watch)

    assert {:error, missing} =
             Jido.Test.Flow.Component.choice(name: "route", options: [valid_option])

    assert missing.details.path == [:fallback]

    assert {:error, condition} =
             Jido.Test.Flow.Component.option(
               name: "ready",
               condition: :truthy,
               action: Hostile.Watch
             )

    assert condition.message =~ "condition"
    refute_received {:hostile_action, _}
  end

  test "a non-Boolean Choice condition never calls either target" do
    assert {:error, error} =
             Exec.run(Hostile.ChoiceNonBoolean, %{condition: "yes"}, %{observer: self()})

    assert error.details.node == "route"
    assert error.phase == :choice_condition
    assert error.details.reason == :invalid_boolean_operand
    refute_received {:hostile_action, _}

    assert Exec.run(Hostile.ChoiceNonBoolean, %{condition: true}) ==
             {:ok, %{branch: :selected}}

    assert Exec.run(Hostile.ChoiceNonBoolean, %{condition: false}) ==
             {:ok, %{branch: :fallback}}
  end

  test "Iterate validates initial and replacement State before another body call" do
    assert {:error, initial_error} =
             Exec.run(Hostile.IterateInitial, %{seed: "wrong type"}, %{observer: self()})

    assert initial_error.details.node == "counter"
    assert initial_error.details.phase == :iterate_state_initial
    refute_received {:hostile_action, _}

    assert {:error, replacement_error} =
             Exec.run(Hostile.IterateReplacement, %{}, %{observer: self()})

    assert replacement_error.details.node == "counter"
    assert replacement_error.details.phase == :iterate_state_update
    assert_receive :bad_state_called
    refute_received :bad_state_called
  end

  test "Iterate rejects a non-Boolean completion value before its body" do
    assert {:error, error} =
             Exec.run(Hostile.IterateCondition, %{condition: "truthy"}, %{observer: self()})

    assert error.details.node == "counter"
    refute_received {:hostile_action, _}
  end

  test "Iterate source rejects a missing while bound and a Flow body target" do
    for {suffix, action, bound, message} <- [
          {"MissingBound", Hostile.Watch, "", "iterate max_iterations must be an integer"},
          {"FlowTarget", Hostile.ValidatedFinalFlow, "max_iterations 2", "Flow component has the wrong target kind"}
        ] do
      module = unique_module(suffix)

      source = """
      defmodule #{inspect(module)} do
        use Jido.Flow, name: "authoring_iterate_#{suffix}"
        flow do
          iterate "counter" do
            state Jido.Joi.object(%{count: Jido.Joi.integer()}), initial: %{count: 0}
            action #{inspect(action)}
            params %{count: state(:count)}
            update %{count: body_result(:count)}
            while state(:count) < 1
            #{bound}
          end
          output result("counter")
        end
      end
      """

      error =
        assert_raise CompileError, fn ->
          AuthoringCompiler.with_compiled(source, fn _modules -> :ok end, modules: [module])
        end

      assert error.file == "authoring_fixture.ex"
      assert Exception.message(error) =~ message
      refute Code.ensure_loaded?(module)
    end
  end

  test "Handoff rejects a second sink, a second Handoff, and a partial output" do
    handoff =
      Jido.Test.Flow.Component.handoff!(name: "route", selector: Components.Expand)

    tail =
      Jido.Test.Flow.Component.step!(name: "tail", action: Components.Echo, needs: ["route"])

    second =
      Jido.Test.Flow.Component.handoff!(
        name: "again",
        selector: Components.Expand
      )

    cases = [
      {[handoff, tail], Ref.result("tail"), "Handoff must be the final component"},
      {[handoff, second], Ref.result("route"), "only one Handoff"},
      {[handoff], %{value: Ref.result("route", :value)}, "complete Handoff result"}
    ]

    for {components, output, message} <- cases do
      assert {:error, error} =
               Jido.Test.Flow.Builder.new(
                 name: "invalid_handoff",
                 components: components,
                 output: output
               )

      assert error.message =~ message
    end

    parent =
      Jido.Test.Flow.Builder.new!(
        name: "handoff_parent",
        components: [
          Jido.Test.Flow.Component.subflow!(
            name: "child",
            flow: Components.HandoffFlow
          )
        ],
        output: Ref.result("child")
      )

    assert {:ok, ^parent} = Jido.Exec.Compiler.validate(parent)
  end

  test "a wrong-kind source declaration reports its own source file and line" do
    module = unique_module("WrongKindSource")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "wrong_kind_source"
      flow do
        map "items", collection: input(:items), action: JidoActionTest.Authoring.Components.Child, params: %{}
        output %{items: result("items")}
      end
    end
    """

    error =
      assert_raise CompileError, fn ->
        AuthoringCompiler.with_compiled(source, fn _modules -> :ok end, modules: [module])
      end

    assert error.file == "authoring_fixture.ex"
    assert error.line == 4
    assert Exception.message(error) =~ "Flow component has the wrong target kind"
    refute Code.ensure_loaded?(module)
  end

  test "only references and needs order a diamond declared in reverse source order" do
    flow = Hostile.Diamond.flow()
    assert flow.components |> Map.keys() |> Enum.sort() == ["left", "right", "root", "sink"]

    assert flow.components |> Graph.canonical_components() |> Enum.map(&elem(&1, 0)) ==
             ["root", "left", "right", "sink"]

    assert {:ok, dependencies} = Flow.dependencies(flow)
    assert dependencies["root"].effective == []
    assert dependencies["left"] == %{references: [], needs: ["root"], effective: ["root"]}
    assert dependencies["right"] == %{references: ["root"], needs: [], effective: ["root"]}

    assert dependencies["sink"] == %{
             references: ["right"],
             needs: ["left"],
             effective: ["left", "right"]
           }

    assert Exec.run(Hostile.Diamond, %{value: 8}, %{observer: self()}, max_concurrency: 2) ==
             {:ok, %{value: 8}}

    assert_receive {:hostile_action, %{id: "root", value: 8}}
    assert_receive {:hostile_action, %{id: first, value: 8}}
    assert_receive {:hostile_action, %{id: second, value: 8}}
    assert MapSet.new([first, second]) == MapSet.new(["left", "right"])
    assert_receive {:hostile_action, %{id: "sink", value: 8}}
    refute_received {:hostile_action, _}
  end

  test "Invoke decisions and ordinary Steps reject continuations" do
    invoke =
      Jido.Test.Flow.Component.invoke!(
        name: "route",
        decision: Hostile.Continues,
        expander: Hostile.Watch,
        params: %{value: Ref.input(:value)}
      )

    invoke_flow =
      Jido.Test.Flow.Builder.new!(
        name: "illegal_decision",
        components: [invoke],
        output: Ref.result("route")
      )

    step_flow =
      Jido.Test.Flow.Builder.new!(
        name: "illegal_step",
        components: [
          Jido.Test.Flow.Component.step!(
            name: "early",
            action: Hostile.Continues,
            params: %{value: Ref.input(:value)}
          )
        ],
        output: Ref.result("early")
      )

    for flow <- [invoke_flow, step_flow] do
      assert {:error, error} = Exec.run(flow, %{value: 1}, %{observer: self()})
      assert error.message == "Action continuations are not supported by Runic execution"
      assert error.details.reason == :unsupported_continuation
      assert_receive :attempted_continuation
      refute_received {:hostile_action, _}
    end
  end

  test "Invoke targets and their parent Flow validate their outputs" do
    invoke = definition(Components.InvokeFlow, "route")

    strict_root =
      Jido.Test.Flow.Builder.new!(
        name: "strict_invoke_root",
        components: [invoke],
        output: Ref.result("route"),
        output_schema: Jido.Joi.object(%{value: Jido.Joi.string()})
      )

    context = %{label: "shared"}

    assert {:error, _root_schema_error} =
             Exec.run(strict_root, %{mode: :finish, value: 5, target: nil}, context)

    permissive_root = %{strict_root | output_schema: Jido.Joi.map()}

    for target <- [Hostile.ValidatedFinal, Hostile.ValidatedFinalFlow] do
      input = %{mode: :continue, value: 5, target: target}
      assert {:error, root_schema_error} = Exec.run(strict_root, input, context)
      assert root_schema_error.details.phase == :flow_output

      assert Exec.run(permissive_root, input, context) ==
               {:ok, %{value: 5, label: "shared"}}

      assert {:error, direct_error} = Exec.run(target, %{value: "bad"}, context)

      assert {:error, continued_error} =
               Exec.run(permissive_root, %{input | value: "bad"}, context)

      assert continued_error.__struct__ == direct_error.__struct__
      assert continued_error.message == direct_error.message
    end
  end

  test "an Invoke target cannot start an Action continuation chain" do
    assert {:error, error} =
             Exec.run(
               Components.InvokeFlow,
               %{mode: :continue, value: 5, target: Hostile.Loop},
               %{observer: self()}
             )

    assert error.message == "Action continuations are not supported by Runic execution"
    assert error.details.reason == :unsupported_continuation
    assert_receive {:loop_started, 5}
    refute_received {:loop_started, _}
  end

  defp definition(module, name) do
    flow = module.flow()
    FlowComponent.component_to_definition({name, Map.fetch!(flow.components, name)})
  end

  defp unique_module(suffix) do
    Module.concat([
      JidoActionTest.Authoring.Hostile.Dynamic,
      "#{suffix}#{System.unique_integer([:positive])}"
    ])
  end
end
