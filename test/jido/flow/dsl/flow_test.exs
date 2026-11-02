defmodule Jido.Flow.DSL.FlowTest.MixedFlow do
  @moduledoc false

  use Jido.Flow, name: "mixed_dsl"

  alias JidoActionTest.Fixtures.Actions.Multiply

  flow do
    step("load",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1},
      meta: %{owner: "dsl"}
    )

    choice "route" do
      option "add" do
        condition(input(:kind) == :add)
        action(JidoActionTest.Fixtures.Actions.Add)
        params(%{value: result("load", :value), amount: 1})
      end

      otherwise action: Multiply, params: %{value: result("load", :value), amount: 1}
    end

    map("mapped",
      collection: input(:items),
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: item(:value), amount: 1},
      on_error: :collect_errors
    )

    reduce "reduced" do
      collection(result("mapped"))
      initial(%{value: 1})
      action(JidoActionTest.Fixtures.Actions.Multiply)
      params(%{value: accumulator(:value), amount: item(:value)})
    end

    iterate "loop" do
      state(Zoi.map(), initial: %{count: 0})
      action(JidoActionTest.Fixtures.Actions.Add)
      params(%{value: state(:count), amount: 1})
      update(%{count: body_result(:value)})
      repeat(1)
    end

    output(result("loop"))
  end
end

defmodule Jido.Flow.DSL.FlowTest.InlineAndExistingFlow do
  @moduledoc false

  use Jido.Flow, name: "inline_and_existing"

  flow do
    step "inline", name <- input(:name) do
      {:ok, %{name: name}}
    end

    step "keyword",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: 1, amount: 2}

    step "field_block" do
      action(JidoActionTest.Fixtures.Actions.Multiply)
      params(%{value: result("keyword", :value), amount: 2})
    end

    step "child",
      action: JidoActionTest.Fixtures.InlineGreetingFlow,
      params: result("inline")

    output(%{message: result("child", :message), value: result("field_block", :value)})
  end
end

defmodule Jido.Flow.DSL.FlowTest do
  use ExUnit.Case, async: false

  alias Jido.Flow.Ref

  test "inline Steps coexist with keyword Steps, field-block Steps, and Subflows" do
    module = Jido.Flow.DSL.FlowTest.InlineAndExistingFlow

    components = module.flow().components

    for name <- ["inline", "keyword", "field_block"] do
      assert %{kind: :call, call: %{kind: :action, params: _params}} = components[name]
    end

    assert %{kind: :call, call: %{kind: :flow, params: _params}} =
             components["child"]

    assert Jido.Exec.run(module, %{name: " Ada "}) ==
             {:ok, %{message: "Hello, Ada!", value: 6}}
  end

  test "step_action returns only canonical Action-backed Step targets" do
    module = Jido.Flow.DSL.FlowTest.InlineAndExistingFlow
    components = module.flow().components

    [inline, keyword, field_block] =
      Enum.map(["inline", "keyword", "field_block"], &components[&1])

    for {name, step} <-
          Enum.zip(["inline", "keyword", "field_block"], [inline, keyword, field_block]) do
      instruction = step.call
      assert module.step_action(name) == instruction.target
    end

    assert module.step_action(:inline) == inline.call.target
    assert module.step_action(:keyword) == JidoActionTest.Fixtures.Actions.Add
    assert module.step_action(:field_block) == JidoActionTest.Fixtures.Actions.Multiply

    for name <- ["child", "unknown", nil, "", 17, %{}, <<255>>, String.duplicate("x", 257)] do
      assert_raise ArgumentError, ~r/expected an Action-backed Step name/, fn ->
        module.step_action(name)
      end
    end

    for name <- ["route", "mapped", "reduced", "loop"] do
      assert_raise ArgumentError, ~r/expected an Action-backed Step name/, fn ->
        Jido.Flow.DSL.FlowTest.MixedFlow.step_action(name)
      end
    end
  end

  test "the unchanged Spark forms lower directly to canonical records" do
    flow = Jido.Flow.DSL.FlowTest.MixedFlow.flow()

    assert %{call: %{params: %{amount: 1}}, meta: %{owner: "dsl"}} =
             flow.components["load"]

    assert %{kind: :choice, needs: []} = flow.components["route"]
    assert %{kind: :map, on_error: :collect_errors} = flow.components["mapped"]
    assert %{kind: :reduce} = flow.components["reduced"]
    assert %{kind: :iterate, max_iterations: 1} = flow.components["loop"]

    assert flow.output == Ref.result("loop")
  end

  test "a Flow module exposes its definition, validation, and convenience helpers" do
    module = Jido.Flow.DSL.FlowTest.MixedFlow

    for {name, arity} <- [
          flow: 0,
          step_action: 1,
          compiled: 0,
          name: 0,
          description: 0,
          schema: 0,
          output_schema: 0,
          validate_params: 1,
          validate_output: 1,
          run: 2
        ] do
      assert function_exported?(module, name, arity)
    end

    for name <- [
          :to_map,
          :validate,
          :validate_executable,
          :dependencies,
          :explain,
          :semantic_identity
        ] do
      refute function_exported?(module, name, 0)
    end
  end

  test "a multi-component Flow requires an explicit output" do
    code = """
    defmodule MissingMultiOutputFlow do
      use Jido.Flow, name: "missing_multi_output"

      flow do
        step "first",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: 1}

        step "second",
          action: JidoActionTest.Fixtures.Actions.Multiply,
          params: %{value: result("first", :value), amount: 2}
      end
    end
    """

    assert_raise CompileError, ~r/Flow output is required/, fn ->
      Code.compile_string(code)
    end
  end

  test "a one-component Flow requires an explicit output" do
    code = """
    defmodule MissingSingleOutputFlow do
      use Jido.Flow, name: "missing_single_output"

      flow do
        step "only",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 10, amount: 1}
      end
    end
    """

    assert_raise CompileError, ~r/Flow output is required/, fn ->
      Code.compile_string(code)
    end
  end

  test "an explicit output selects a result before the last component" do
    code = """
    defmodule ExplicitOutputSelectsFirstFlow do
      use Jido.Flow, name: "explicit_output_selects_first"

      flow do
        step "first",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1, amount: 1}

        step "second",
          action: JidoActionTest.Fixtures.Actions.Multiply,
          params: %{value: result("first", :value), amount: 2}

        output result("first")
      end
    end
    """

    [{module, _bytecode}] = Code.compile_string(code)

    assert module.flow().output == Ref.result("first")
    assert Jido.Exec.run(module) == {:ok, %{value: 2}}
  end

  test "an explicit nil output is not treated as an omitted output" do
    for {module, output} <- [
          {ExplicitNilOutputFlow, "output nil"},
          {ExplicitValueNilOutputFlow, "output value(nil)"}
        ] do
      code = """
      defmodule #{inspect(module)} do
        use Jido.Flow, name: "explicit_nil_output"

        flow do
          step "work",
            action: JidoActionTest.Fixtures.Actions.Add,
            params: %{value: 1, amount: 1}

          #{output}
        end
      end
      """

      assert_raise CompileError, ~r/Flow output is required/, fn ->
        Code.compile_string(code)
      end
    end
  end

  test "Flow output is required when no block is declared" do
    code = """
    defmodule MissingOutputFlow do
      use Jido.Flow, name: "missing_output"

      flow do
      end
    end
    """

    assert_raise CompileError, ~r/Flow output is required/, fn -> Code.compile_string(code) end
  end

  test "negative number literals match the data definition form" do
    [{module, _binary}] =
      Code.compile_string("""
      defmodule NegativeLiteralFlow do
        use Jido.Flow, name: "negative_literals"

        flow do
          step "echo",
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{offset: -1, scale: -2.5, items: [-3]}

          output result("echo")
        end
      end
      """)

    data =
      Jido.Flow.new!(%{
        name: "negative_literals",
        components: [
          %{
            kind: :step,
            name: "echo",
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{offset: -1, scale: -2.5, items: [-3]}
          }
        ],
        output: Jido.Flow.Ref.result("echo")
      })

    assert Jido.Flow.semantic_identity(module.flow()) == Jido.Flow.semantic_identity(data)
  end

  test "atom names and non-atom meta keys match the data definition form" do
    [{module, _binary}] =
      Code.compile_string("""
      defmodule AtomNameMetaFlow do
        use Jido.Flow, name: "atom_name_meta"

        flow do
          step :load,
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{},
            meta: %{"ui" => %{"x" => 1}, 1 => :first}

          map :items,
            collection: input(:items),
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{item: item()}

          output %{load: result("load"), items: result("items")}
        end
      end
      """)

    data =
      Jido.Flow.new!(%{
        name: "atom_name_meta",
        components: [
          %{
            kind: :step,
            name: "load",
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{},
            meta: %{"ui" => %{"x" => 1}, 1 => :first}
          },
          %{
            kind: :map,
            name: "items",
            collection: Jido.Flow.Ref.input(:items),
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{item: Jido.Flow.Ref.item()}
          }
        ],
        output: %{load: Jido.Flow.Ref.result("load"), items: Jido.Flow.Ref.result("items")}
      })

    assert Jido.Flow.to_map(module.flow()) == Jido.Flow.to_map(data)
  end

  test "empty lists compile and execute as data across Flow declarations" do
    code = """
    defmodule EmptyListLiteralFlow do
      use Jido.Flow, name: "empty_list_literals"

      flow do
        step "echo",
          action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
          params: %{items: [], nested: [[], %{items: []}]},
          needs: []

        map "mapped",
          collection: [],
          action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
          params: %{item: item()}

        reduce "reduced" do
          collection([])
          initial(%{items: []})
          action(JidoActionTest.Fixtures.Actions.EchoParamsAction)
          params(accumulator())
        end

        iterate "loop" do
          state(Zoi.map(), initial: %{items: []})
          action(JidoActionTest.Fixtures.Actions.EchoParamsAction)
          params(state())
          update(body_result())
          while(state(:items) != [])
          max_iterations(1)
        end

        output(%{
          items: [],
          echo: result("echo"),
          mapped: result("mapped"),
          reduced: result("reduced"),
          loop: result("loop")
        })
      end
    end
    """

    [{module, _bytecode}] = Code.compile_string(code)

    assert {:ok,
            %{
              items: [],
              echo: %{items: [], nested: [[], %{items: []}]},
              mapped: [],
              reduced: %{items: []},
              loop: %{state: %{items: []}, iterations: 0, output: nil}
            }} = Jido.Exec.run(module)
  end

  test "an invalid Handoff output points to the output declaration" do
    code = """
    defmodule InvalidHandoffOutputSourceFlow do
      use Jido.Flow, name: "invalid_handoff_output_source"

      flow do
        handoff "next",
          selector: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1}

        output(%{value: result("next")})
      end
    end
    """

    output_line =
      code
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "output("))
      |> Kernel.+(1)

    error =
      assert_raise CompileError, ~r/Flow output must be the complete Handoff result/, fn ->
        Code.compile_string(code)
      end

    assert error.line == output_line
  end

  test "a second Handoff points to its declaration" do
    code = """
    defmodule DuplicateHandoffSourceFlow do
      use Jido.Flow, name: "duplicate_handoff_source"

      flow do
        handoff "first",
          selector: JidoActionTest.Fixtures.Actions.Add,
          params: %{}

        handoff "second",
          selector: JidoActionTest.Fixtures.Actions.Add,
          params: %{}

        output(result("second"))
      end
    end
    """

    source_file = "duplicate_handoff_source.ex"

    second_handoff_line =
      code
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "handoff \"second\""))
      |> Kernel.+(1)

    error =
      assert_raise CompileError, ~r/only one Handoff component/, fn ->
        Code.compile_string(code, source_file)
      end

    assert error.file == source_file
    assert error.line == second_handoff_line
  end

  test "Flow declaration macros reject duplicate and non-keyword options" do
    duplicate_options = """
    defmodule DuplicateStepOptionsFlow do
      use Jido.Flow, name: "duplicate_step_options"

      flow do
        step("add",
          action: JidoActionTest.Fixtures.Actions.Add,
          action: JidoActionTest.Fixtures.Actions.Add
        )

        output(result("add"))
      end
    end
    """

    assert_raise CompileError, ~r/duplicate Flow declaration field: :action/, fn ->
      Code.compile_string(duplicate_options)
    end

    non_keyword_options = """
    defmodule NonKeywordStepOptionsFlow do
      use Jido.Flow, name: "non_keyword_step_options"

      flow do
        step("add", :invalid)
        output(result("add"))
      end
    end
    """

    assert_raise CompileError, ~r/Flow declaration options must be a keyword list/, fn ->
      Code.compile_string(non_keyword_options)
    end
  end

  test "a Flow module in a Choice Action slot is a source-aware compile error" do
    code = """
    defmodule NestedChoiceTargetFlow do
      use Jido.Flow, name: "nested_choice_target"

      flow do
        choice "route" do
          option "nested" do
            condition(1 == 1)
            action(JidoActionTest.Fixtures.NestedFlow)
            params(%{value: 1})
          end

          otherwise action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}
        end

        output(result("route"))
      end
    end
    """

    error =
      assert_raise CompileError, ~r/wrong target kind/, fn -> Code.compile_string(code) end

    assert error.line == 6
  end

  test "an invalid Choice fallback points to the otherwise declaration" do
    code = """
    defmodule InvalidChoiceFallbackTargetFlow do
      use Jido.Flow, name: "invalid_choice_fallback_target"

      flow do
        choice "route" do
          option "valid" do
            condition(1 == 1)
            action(JidoActionTest.Fixtures.Actions.Add)
            params(%{value: 1})
          end

          otherwise action: JidoActionTest.Fixtures.NestedFlow, params: %{value: 1}
        end

        output(result("route"))
      end
    end
    """

    source_file = "invalid_choice_fallback.ex"

    otherwise_line =
      code
      |> String.split("\n")
      |> Enum.find_index(&String.contains?(&1, "otherwise action:"))
      |> Kernel.+(1)

    error =
      assert_raise CompileError, ~r/wrong target kind/, fn ->
        Code.compile_string(code, source_file)
      end

    assert error.file == source_file
    assert error.line == otherwise_line
  end

  test "output must be the last declaration" do
    code = """
    defmodule OutputBeforeStepFlow do
      use Jido.Flow, name: "output_before_step"

      flow do
        output(%{})
        step "add", action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}
      end
    end
    """

    assert_raise CompileError, ~r/output must be the final Flow declaration/, fn ->
      Code.compile_string(code)
    end
  end

  test "Choice requires options and a fallback" do
    no_options = """
    defmodule ChoiceWithoutOptionsFlow do
      use Jido.Flow, name: "choice_without_options"

      flow do
        choice "route" do
          otherwise action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}
        end

        output(result("route"))
      end
    end
    """

    assert_raise CompileError, ~r/choice must declare at least one option/, fn ->
      Code.compile_string(no_options)
    end

    no_fallback = """
    defmodule ChoiceWithoutFallbackFlow do
      use Jido.Flow, name: "choice_without_fallback"

      flow do
        choice "route" do
          option "yes",
            condition: 1 == 1,
            action: JidoActionTest.Fixtures.Actions.Add,
            params: %{value: 1}
        end

        output(result("route"))
      end
    end
    """

    assert_raise CompileError, ~r/choice must declare otherwise/, fn ->
      Code.compile_string(no_fallback)
    end
  end

  test "Iterate requires valid state and termination data" do
    cases = [
      {"""
       iterate "loop" do
         action(JidoActionTest.Fixtures.Actions.Add)
         params(%{value: 1})
         repeat(1)
       end
       """, "iterate must declare one state"},
      {"""
       iterate "loop" do
         state(Zoi.map(), initial: %{})
         action(JidoActionTest.Fixtures.Actions.Add)
         params(%{value: 1})
         while(1 == 1)
       end
       """, "iterate max_iterations must be an integer"},
      {"""
       iterate "loop" do
         state(Zoi.map(), initial: %{})
         action(JidoActionTest.Fixtures.Actions.Add)
         params(%{value: 1})
         repeat(1)
         max_iterations(1)
       end
       """, "iterate repeat must not set max_iterations"},
      {"""
       iterate "loop" do
         state(Zoi.map(), initial: %{})
         action(JidoActionTest.Fixtures.Actions.Add)
         params(%{value: 1})
       end
       """, "iterate requires exactly one of while or repeat"}
    ]

    cases
    |> Enum.with_index()
    |> Enum.each(fn {{iterate, message}, index} ->
      code = """
      defmodule InvalidTerminationFlow#{index} do
        use Jido.Flow, name: "invalid_termination_#{index}"

        flow do
          #{iterate}
          output(result("loop"))
        end
      end
      """

      assert_raise CompileError, ~r/#{message}/, fn -> Code.compile_string(code) end
    end)
  end

  test "the lowerer reports invalid expressions and unavailable step modules" do
    invalid_expression = """
    defmodule InvalidOutputExpressionFlow do
      use Jido.Flow, name: "invalid_output_expression"

      flow do
        output(Date.utc_today())
      end
    end
    """

    assert_raise CompileError, ~r/unsupported Flow expression/, fn ->
      Code.compile_string(invalid_expression)
    end

    missing_module = """
    defmodule MissingStepModuleFlow do
      use Jido.Flow, name: "missing_step_module"

      flow do
        step "missing", action: Jido.Flow.NotARealModule, params: %{}
        output(result("missing"))
      end
    end
    """

    assert_raise CompileError, ~r/step action module could not be compiled/, fn ->
      Code.compile_string(missing_module)
    end
  end

  test "scalar and ordered list needs lower through keyword and block fields" do
    code = """
    defmodule ValidWhileAndNeedsFlow do
      use Jido.Flow, name: "valid_while_and_needs"

      flow do
        step "first", action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}

        step "second",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1},
          needs: "first"

        iterate "loop" do
          state(Zoi.map(), initial: %{value: 0})
          action(JidoActionTest.Fixtures.Actions.Add)
          params(%{value: state(:value)})
          needs(["second", "first"])
          update(body_result())
          while(state(:value) < 1)
          max_iterations(2)
        end

        output(result("loop"))
      end
    end
    """

    [{module, _bytecode}] = Code.compile_string(code)

    assert %{kind: :call, needs: []} = module.flow().components["first"]
    assert %{kind: :call, needs: ["first"]} = module.flow().components["second"]

    assert %{kind: :iterate, needs: ["second", "first"]} =
             module.flow().components["loop"]

    assert %{[:components, "loop", :state] => %{line: line}} =
             module.__jido_flow_source_map__()

    assert is_integer(line)
  end

  test "the module DSL rejects after instead of converting it" do
    code = """
    defmodule LegacyAfterFlow do
      use Jido.Flow, name: "legacy_after"

      flow do
        step "first", action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 1}

        step "second",
          action: JidoActionTest.Fixtures.Actions.Add,
          params: %{value: 1},
          after: "first"

        output(result("second"))
      end
    end
    """

    assert_raise Spark.Error.DslError, ~r/after/, fn -> Code.compile_string(code) end
  end

  test "invalid module configuration is a compile error" do
    code = """
    defmodule InvalidFlowConfiguration do
      use Jido.Flow, name: 123
      flow do
        output(%{})
      end
    end
    """

    assert_raise CompileError, ~r/Flow configuration validation failed/, fn ->
      Code.compile_string(code)
    end

    non_map_code = """
    defmodule NonMapFlowConfiguration do
      use Jido.Flow, :invalid
      flow do
        output(%{})
      end
    end
    """

    assert_raise CompileError, ~r/Flow configuration validation failed/, fn ->
      Code.compile_string(non_map_code)
    end
  end
end
