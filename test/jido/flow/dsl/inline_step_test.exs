defmodule Jido.Flow.DSL.InlineStepTest do
  use Covenant.Case, component: "jido_action.inline", async: false

  alias Jido.Flow.DSL.{ValueParser, InlineStep}
  alias Jido.Flow.Ref

  @source_file "inline_header.ex"
  @source_line 40

  defmodule NameSource do
    defmacro literal_name do
      send(self(), :inline_name_macro_expanded)
      "macro_name"
    end

    def expression_name do
      send(self(), :inline_name_expression_evaluated)
      "expression_name"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "Step names expand or evaluate once in either form" do
    for {expression, marker, name} <- [
          {"#{inspect(NameSource)}.literal_name()", :inline_name_macro_expanded, "macro_name"},
          {"#{inspect(NameSource)}.expression_name()", :inline_name_expression_evaluated, "expression_name"}
        ],
        inline? <- [false, true] do
      owner = unique_owner("EvaluatedName")

      declaration =
        if inline?,
          do: "step #{expression}, value <- 1, do: {:ok, %{value: value + 1}}",
          else: "step #{expression}, action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1}"

      compile_source(flow_source(owner, declaration, "require #{inspect(NameSource)}"))
      assert_received ^marker
      refute_received ^marker
      assert {:ok, %{value: 2}} = Jido.Exec.run(owner.step_action(name), %{value: 1})
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "string attribute names survive conversion from explicit to inline Steps" do
    for declaration <- [
          "step @step_name, action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1}",
          "step @step_name, value <- 1, do: {:ok, %{value: value + 1}}"
        ] do
      owner = unique_owner("AttributeName")

      compile_source("""
      defmodule #{inspect(owner)} do
        use Jido.Flow, name: "attribute_name"
        @step_name "increment"
        flow do
          #{declaration}
          output result("increment")
        end
      end
      """)

      assert %{call: %{target: action, params: _params}} =
               owner.flow().components["increment"]

      assert owner.step_action("increment") == action
      assert {:ok, %{value: 2}} = Jido.Exec.run(owner, %{})
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline names and bodies retain attributes at each declaration" do
    owner = unique_owner("AttributeOrder")

    declarations = """
    step @step_name, [], do: {:ok, %{name: @step_name}}
    @step_name "second"
    step @step_name, [], do: {:ok, %{name: @step_name}}
    """

    compile_source(flow_source(owner, declarations, ~s(@step_name "first")))

    assert Map.keys(owner.flow().components) |> Enum.sort() == ["first", "second"]

    for name <- ["first", "second"] do
      {target, _} = generated_identity(owner, name)
      assert owner.step_action(name) == target
      assert target.name() == name
      assert {:ok, %{name: ^name}} = Jido.Exec.run(target, %{})
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "attribute names detect mixed duplicates at the second declaration" do
    inline = "step @step_name, [], do: {:ok, %{}}"
    explicit = "step @step_name, action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1}"

    for {first, second} <- [{inline, explicit}, {explicit, inline}, {inline, inline}] do
      owner = unique_owner("AttributeDuplicate")
      {target, _} = generated_identity(owner, "same")
      source = flow_source(owner, first <> "\n" <> second, ~s(@step_name "same"))

      error =
        assert_raise CompileError, ~r/duplicate Step name: "same"/, fn ->
          compile_source(source)
        end

      assert error.file == "inline_compile.ex"
      assert error.line == 6

      if first == inline,
        do:
          assert(
            target.__jido_inline_action__() ==
              {owner, [host: Jido.Flow, step: "same", role: :action]}
          ),
        else: refute(Code.ensure_loaded?(target))
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "invalid evaluated inline names report the Step location" do
    for value <- ["", nil, 123] do
      owner = unique_owner("InvalidAttributeName")

      source =
        flow_source(owner, "step @step_name, [], do: {:ok, %{}}", "@step_name #{inspect(value)}")

      error = assert_raise CompileError, fn -> compile_source(source) end
      assert error.file == "inline_compile.ex"
      assert error.line == 5
      assert error.description =~ "name"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a dynamic explicit name is registered before a later inline declaration" do
    owner = unique_owner("DynamicDuplicate")
    {target, _} = generated_identity(owner, "expression_name")

    source = """
    defmodule #{inspect(owner)} do
      use Jido.Flow, name: "dynamic_duplicate"
      flow do
        step #{inspect(NameSource)}.expression_name(), action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1}
        step "expression_name", [], do: {:ok, %{}}
        output(%{})
      end
    end
    """

    error =
      assert_raise CompileError, ~r/duplicate Step name: "expression_name"/, fn ->
        compile_source(source)
      end

    assert error.line == 5
    assert_received :inline_name_expression_evaluated
    refute_received :inline_name_expression_evaluated
    refute Code.ensure_loaded?(target)
  end

  @tag obligation: "jido_action.inline.I2"
  test "a Step in a false authoring branch does not reserve its name" do
    for unused <- [
          ~s(step "same", action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1}),
          ~s(step "same", [], do: {:ok, %{value: :unused}}),
          "step #{inspect(NameSource)}.expression_name(), [], do: {:ok, %{}}"
        ] do
      owner = unique_owner("Conditional")

      declarations = """
      if false do
        #{unused}
      end
      step "same", [], do: {:ok, %{value: :used}}
      """

      compile_source(flow_source(owner, declarations))
      assert %{kind: :call} = owner.flow().components["same"]
      assert owner.step_action("same").run(%{}, %{}) == {:ok, %{value: :used}}
      refute_received :inline_name_expression_evaluated
      {unused_target, _} = generated_identity(owner, "expression_name")
      refute Code.ensure_loaded?(unused_target)
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "duplicate Steps fail before a second inline target can replace the first" do
    inline = ~s(step :same, [], do: {:ok, %{value: :first}})
    replacement = ~s(step "same", [], do: {:ok, %{value: :second}})
    keyword = ~s(step "same", action: Jido.Test.Action.Fixtures.Actions.Add, params: %{value: 1})

    block =
      "step \"same\" do\n action(Jido.Test.Action.Fixtures.Actions.Add)\n params(%{value: 1})\n end"

    for {first, second} <- [
          {inline, replacement},
          {inline, keyword},
          {keyword, inline},
          {inline, block},
          {block, inline}
        ] do
      owner = unique_owner("Duplicate")
      target = generated_identity(owner, "same") |> elem(0)

      assert_raise CompileError, ~r/duplicate Step name: "same"/, fn ->
        compile_source(flow_source(owner, first <> "\n" <> second))
      end

      if first == inline do
        assert target.__jido_inline_action__() ==
                 {owner, [host: Jido.Flow, step: "same", role: :action]}
      else
        refute Code.ensure_loaded?(target)
      end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "foreign generated module names cannot be overwritten" do
    owner = unique_owner("Foreign")
    {target, _function} = generated_identity(owner, "same")
    compile_source("defmodule #{inspect(target)} do\n def untouched, do: :foreign\nend")

    assert_raise CompileError, ~r/generated inline Step module.*already belongs/, fn ->
      compile_source(flow_source(owner, ~s(step "same", [], do: {:ok, %{}})))
    end

    assert target.untouched() == :foreign
    refute function_exported?(target, :run, 2)
  end

  @tag obligation: "jido_action.inline.I2"
  test "generated owner functions and lookup reject user clauses before and after declarations" do
    for position <- [:before, :after], kind <- [:body, :lookup], visibility <- [:def, :defp] do
      owner = unique_owner("Reserved")
      {_target, body_function} = generated_identity(owner, "same")
      {function, arity} = if kind == :body, do: {body_function, 2}, else: {:step_action, 1}
      clause = definition_source(visibility, function, List.duplicate({:_, [], nil}, arity))
      declaration = ~s(step "same", [], do: {:ok, %{}})
      {before, after_code} = if position == :before, do: {clause, ""}, else: {"", clause}
      source = flow_source(owner, declaration, before, after_code)

      if kind == :lookup and visibility == :defp do
        # The forward public head lets Elixir reject a private clause before
        # the reserved-function callback. Require its source-aware diagnostic.
        clause_line =
          source |> String.split("\n") |> Enum.find_index(&(String.trim(&1) == clause))

        {_result, diagnostics} =
          Code.with_diagnostics(fn ->
            assert_raise CompileError, fn -> compile_source(source) end
          end)

        assert Enum.any?(diagnostics, fn diagnostic ->
                 diagnostic.severity == :error and
                   diagnostic.message ==
                     "defp step_action/1 already defined as def in inline_compile.ex:2" and
                   Path.basename(diagnostic.file) == "inline_compile.ex" and
                   diagnostic_line(diagnostic) == clause_line + 1
               end)
      else
        # Elixir itself rejects a private clause after a public generated body
        # before it calls the definition callback.
        message =
          if position == :after and kind == :body and visibility == :defp,
            do: ~r/cannot compile file|already defined as def/,
            else: ~r/reserved Flow function.*#{function}/

        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert_raise CompileError, message, fn -> compile_source(source) end
        end)
      end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "lookup is reserved even when it is defined before use Jido.Flow" do
    owner = unique_owner("EarlyLookup")

    assert_raise CompileError, ~r/reserved Flow function.*step_action/, fn ->
      compile_source("""
      defmodule #{inspect(owner)} do
        def step_action(_), do: :user_clause
        use Jido.Flow, name: "early_lookup"
        flow do
          step "same", action: Jido.Test.Action.Fixtures.Actions.Add
          output(%{})
        end
      end
      """)
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "default arguments that define reserved arities report the user declaration" do
    for {kind, position} <- [{:lookup, :before}, {:lookup, :after}, {:body, :after}],
        visibility <- [:def, :defp],
        defaults <- [1, 2] do
      owner = unique_owner("DefaultConflict")
      {_target, body_function} = generated_identity(owner, "same")
      {function, arity} = if kind == :lookup, do: {:step_action, 1}, else: {body_function, 2}
      required = List.duplicate({:_, [], nil}, arity)
      optional = List.duplicate({:\\, [], [{:_, [], nil}, []]}, defaults)
      clause = definition_source(visibility, function, required ++ optional)

      {before, after_code} = if position == :before, do: {clause, ""}, else: {"", clause}
      source = flow_source(owner, ~s(step "same", [], do: {:ok, %{}}), before, after_code)
      clause_line = source |> String.split("\n") |> Enum.find_index(&(String.trim(&1) == clause))

      {error, diagnostics} =
        Code.with_diagnostics(fn ->
          assert_raise CompileError, fn -> compile_source(source) end
        end)

      if error.description =~ "reserved Flow function" do
        assert error.description =~ "#{function}/#{arity}"
        assert error.file == "inline_compile.ex"
        assert error.line == clause_line + 1
      else
        # Elixir can reject a private default-generated clause before our callback.
        assert visibility == :defp
        definition_line = if kind == :lookup, do: 2, else: 5

        assert Enum.any?(diagnostics, fn diagnostic ->
                 diagnostic.severity == :error and
                   diagnostic.message ==
                     "defp #{function}/#{arity} already defined as def in inline_compile.ex:#{definition_line}" and
                   Path.basename(diagnostic.file) == "inline_compile.ex" and
                   diagnostic_line(diagnostic) == clause_line + 1
               end)
      end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "an earlier body helper with default arguments cannot be replaced by an inline Step" do
    for visibility <- [:def, :defp] do
      owner = unique_owner("EarlyDefaultBody")
      {target, function} = generated_identity(owner, "same")
      args = List.duplicate({:_, [], nil}, 2) ++ [{:\\, [], [{:_, [], nil}, []]}]
      helper = definition_source(visibility, function, args)
      source = flow_source(owner, ~s(step "same", [], do: {:ok, %{}}), helper)

      error =
        assert_raise CompileError, ~r/reserved Flow function.*#{function}\/2/, fn ->
          compile_source(source)
        end

      # The Step is where this computed function name first becomes reserved.
      assert error.file == "inline_compile.ex"
      assert error.line == 5
      refute Code.ensure_loaded?(target)
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "default arguments with no reserved arity remain valid" do
    owner = unique_owner("AllowedDefaults")
    helper = "def step_action(name, value, opts \\\\ []), do: {name, value, opts}"
    compile_source(flow_source(owner, ~s(step "same", [], do: {:ok, %{}}), "", helper))

    assert owner.step_action("same", :value) == {"same", :value, []}
    assert owner.step_action("same", :value, [:option]) == {"same", :value, [:option]}
    assert {:ok, %{}} = owner.step_action("same").run(%{}, %{})
  end

  @tag obligation: "jido_action.inline.I2"
  test "bounded target names preserve long, punctuation, and Unicode names across owners" do
    names = [String.duplicate("x", 256), "hello-world?!", "café/世界"]
    owner = unique_owner(String.duplicate("L", 150))
    other = unique_owner("Other")
    declarations = Enum.map_join(names, "\n", &"step #{inspect(&1)}, [], do: {:ok, %{}}")
    compile_source(flow_source(owner, declarations))
    compile_source(flow_source(other, declarations))

    for name <- names do
      target = owner.step_action(name)
      assert target != other.step_action(name)
      assert byte_size(Atom.to_string(target)) < 128
      assert target.name() == name

      assert target.__jido_inline_action__() ==
               {owner, [host: Jido.Flow, step: name, role: :action]}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "normal recompilation keeps identity and replaces the body" do
    owner = unique_owner("Recompiled")
    compile_source(flow_source(owner, ~s(step "same", [], do: {:ok, %{version: 1}})))
    target = owner.step_action("same")

    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      compile_source(flow_source(owner, ~s(step "same", [], do: {:ok, %{version: 2}})))
    end)

    assert owner.step_action("same") == target
    assert target.run(%{}, %{}) == {:ok, %{version: 2}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "repeated runtime access creates no target modules or atoms from unknown names" do
    owner = Jido.Test.Flow.Fixtures.InlineGreetingFlow

    unknown_names =
      for n <- 1..100, do: "unknown_inline_step_#{n}_#{System.unique_integer([:positive])}"

    access = fn ->
      for name <- unknown_names do
        assert_raise ArgumentError, fn -> owner.step_action(name) end
      end

      assert is_atom(owner.step_action(:greet))
      assert {:ok, _} = Jido.Flow.validate(owner.flow())
      assert {:ok, _} = Jido.Exec.run(owner, %{name: "Ada"})
    end

    access.()
    targets = generated_modules()
    for _ <- 1..3, do: access.()
    assert generated_modules() == targets

    for name <- unknown_names do
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline bindings compile and run through ordinary Steps with inferred dependencies" do
    flow = Jido.Test.Flow.Fixtures.InlineGreetingFlow.flow()
    assert %{call: %{target: action, params: params}} = flow.components["normalize"]
    assert %{kind: :call} = flow.components["greet"]

    assert is_atom(action)
    assert params == %{name: Ref.input(:name)}

    assert Jido.Exec.run(Jido.Test.Flow.Fixtures.InlineGreetingFlow, %{name: " Ada "}) ==
             {:ok, %{message: "Hello, Ada!"}}

    assert {:ok, dependencies} =
             Jido.Flow.dependencies(Jido.Test.Flow.Fixtures.InlineGreetingFlow.flow())

    assert dependencies["greet"] == %{
             needs: [],
             references: ["normalize"],
             effective: ["normalize"]
           }
  end

  @tag obligation: "jido_action.inline.I2"
  test "bodies retain the declaration's aliases, imports, helpers, module, and attributes" do
    module = Jido.Test.Flow.Fixtures.InlineLexicalFlow
    assert {:ok, result} = Jido.Exec.run(module, %{name: " Ada "})

    assert result == %{
             value: "[ADA!?]",
             module: module,
             prefix: "before",
             qualified: %{name: "body", value: " Ada "},
             local_import: %{name: "local", value: "[ADA!?]"}
           }

    assert module.current_prefix() == "after"
    assert Map.keys(module.flow().components) |> Enum.sort() == ["lexical", "local_import"]
  end

  for namespace <- [
        Jido.Flow.DSLHelpers,
        Spark.DslHelpers,
        Jido.Flow.DSL.Helpers,
        Spark.Dsl.Helpers
      ] do
    @tag obligation: "jido_action.inline.I2"
    test "inline bodies retain imports from #{inspect(namespace)}" do
      helper = Module.concat(unquote(namespace), "Inline#{System.unique_integer([:positive])}")
      owner = unique_owner("SimilarNamespace")

      on_exit(fn ->
        :code.purge(helper)
        :code.delete(helper)
      end)

      compile_source("""
      defmodule #{inspect(helper)} do
        def prefix_marker, do: :retained
      end
      """)

      declaration = ~s|step "same", [], do: {:ok, %{marker: prefix_marker()}}|
      compile_source(flow_source(owner, declaration, "import #{inspect(helper)}"))

      assert owner.step_action("same").run(%{}, %{}) == {:ok, %{marker: :retained}}
      assert %{kind: :call} = owner.flow().components["same"]
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "canonical inline Steps contain only ordinary Action author data" do
    flow = Jido.Test.Flow.Fixtures.InlineGreetingFlow.flow()
    map = Jido.Flow.to_map(flow)

    for {name, %{call: %{target: action, params: _params}} = node} <- flow.components do
      assert Map.keys(node) |> Enum.sort() == [:call, :kind, :meta, :needs]
      assert is_atom(action)
      assert action.name() == name
      assert Jido.Joi.Schema.kind(action.schema()) == :map
      assert Jido.Joi.Schema.kind(action.output_schema()) == :map
    end

    assert canonical_data?(map)
  end

  @tag obligation: "jido_action.inline.I2"
  test "compiler, validation, and inspection do not run inline work" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.InertFlow do
      use Jido.Flow, name: "inline_inert"
      flow do
        step "mark", ctx <- context() do
          send(ctx.owner, {:inline_work, ctx.marker})
          {:ok, %{worked: true}}
        end
        output(result("mark"))
      end
    end
    """

    compile_source(source)
    module = Module.concat(__MODULE__, InertFlow)
    flow = module.flow()
    assert {:ok, ^flow} = Jido.Flow.validate(flow)
    assert {:ok, ^flow} = Jido.Exec.Compiler.validate(flow)
    assert {:ok, _} = Jido.Flow.explain(flow)
    assert {:ok, _} = Jido.Exec.compile(flow)
    assert is_map(Jido.Flow.to_map(flow))
    refute_received {:inline_work, _}

    marker = make_ref()
    assert {:ok, %{worked: true}} = Jido.Exec.run(module, %{}, %{owner: self(), marker: marker})
    assert_received {:inline_work, ^marker}
  end

  @tag obligation: "jido_action.inline.I2"
  test "undefined body calls report the user body file and line" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.UndefinedFlow do
      use Jido.Flow, name: "inline_undefined"
      flow do
        step "bad", [] do
          missing_inline_function()
        end
        output(result("bad"))
      end
    end
    """

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        assert_raise CompileError, fn -> compile_source(source, "inline_undefined.ex") end
      end)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and
               diagnostic.message =~ "undefined function missing_inline_function/0" and
               Path.basename(diagnostic.file) == "inline_undefined.ex" and
               diagnostic_line(diagnostic) == 5
           end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "declaration imports are not available inside the body function" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.NoDeclarationFlow do
      use Jido.Flow, name: "inline_no_declaration"
      flow do
        step "bad", [] do
          output(%{})
        end
        output(result("bad"))
      end
    end
    """

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        assert_raise CompileError, fn -> compile_source(source, "inline_no_declaration.ex") end
      end)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and diagnostic.message =~ "undefined function output/1" and
               diagnostic_line(diagnostic) == 5
           end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "unused user variables retain warnings at the header line" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.UnusedFlow do
      use Jido.Flow, name: "inline_unused"
      flow do
        step "unused", user_value <- input(:value) do
          body_value = :unused
          {:ok, %{}}
        end
        output(result("unused"))
      end
    end
    """

    {_modules, diagnostics} =
      Code.with_diagnostics(fn -> compile_source(source, "inline_unused.ex") end)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :warning and diagnostic.message =~ "user_value" and
               diagnostic.message =~ "unused" and
               Path.basename(diagnostic.file) == "inline_unused.ex" and
               diagnostic_line(diagnostic) == 4
           end)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :warning and diagnostic.message =~ "body_value" and
               Path.basename(diagnostic.file) == "inline_unused.ex" and
               diagnostic_line(diagnostic) == 5
           end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "all inline macro arities lower their params, needs, and meta through normal Steps" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.BindingFormsFlow do
      use Jido.Flow, name: "inline_binding_forms"
      alias URI, as: Address

      flow do
        step :seed, [] do
          {:ok, %{ready: true}}
        end

        step "one", name <- input(:name), needs: ["seed"], meta: %{form: "one"} do
          {:ok, %{name: name}}
        end

        step "two", [name <- result("one", :name), ctx <- context()] do
          {:ok, %{name: name <> ctx.suffix}}
        end

        step "two_options", [name <- result("two", :name), count <- input(:count)],
          needs: ["seed"], meta: %{form: "two"} do
          {:ok, %{name: name, count: count}}
        end

        step "list", [name <- result("two_options", :name), count <- input(:count), ctx <- context()],
          meta: %{form: "list"} do
          repeat = fn value -> String.duplicate(value, count) end
          {:ok, %{name: repeat.(name), suffix: ctx.suffix}}
        end

        step "pattern", %{uri: %Address{path: path}, kind: :person} <- input() do
          {:ok, %{path: path}}
        end

        output(%{list: result("list"), path: result("pattern", :path)})
      end
    end
    """

    compile_source(source)
    module = Module.concat(__MODULE__, BindingFormsFlow)
    components = module.flow().components

    [seed, one, two, two_options, list, pattern] =
      Enum.map(["seed", "one", "two", "two_options", "list", "pattern"], &components[&1])

    assert call_params(seed) == %{}
    assert one.needs == ["seed"]
    assert one.meta == %{form: "one"}
    assert call_params(two) == %{name: Ref.result("one", :name), ctx: Ref.context()}
    assert two_options.needs == ["seed"]
    assert two_options.meta == %{form: "two"}
    assert list.meta == %{form: "list"}
    assert call_params(pattern) == Ref.input([])

    assert Jido.Exec.run(
             module,
             %{name: "Ada", count: 2, uri: URI.parse("/home"), kind: :person},
             %{suffix: "!"}
           ) ==
             {:ok, %{list: %{name: "Ada!Ada!", suffix: "!"}, path: "/home"}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "a runtime raise keeps the user body file and line" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.RaisingFlow do
      use Jido.Flow, name: "inline_raising"
      flow do
        step "raise", [] do
          raise "inline body failed"
        end
        output(result("raise"))
      end
    end
    """

    compile_source(source, "inline_raise.ex")
    assert {:error, error} = Jido.Exec.run(__MODULE__.RaisingFlow)
    assert %Splode.Stacktrace{stacktrace: stacktrace} = error.stacktrace

    assert Enum.any?(stacktrace, fn
             {__MODULE__.RaisingFlow, _function, _arity, location} ->
               to_string(location[:file]) == "inline_raise.ex" and location[:line] == 5

             _frame ->
               false
           end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "normal invalid nested patterns are rejected by the owner function compiler" do
    source = """
    defmodule Jido.Flow.DSL.InlineStepTest.BadPatternFlow do
      use Jido.Flow, name: "inline_bad_pattern"
      flow do
        step "bad", %{name: String.trim(name)} <- input() do
          {:ok, %{name: name}}
        end
        output(result("bad"))
      end
    end
    """

    {_result, diagnostics} =
      Code.with_diagnostics(fn ->
        assert_raise CompileError, fn -> compile_source(source, "inline_pattern.ex") end
      end)

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and diagnostic.message =~ "inside a match" and
               Path.basename(diagnostic.file) == "inline_pattern.ex" and
               diagnostic_line(diagnostic) == 4
           end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "one named binding retains the input and body syntax" do
    {:step, _, [_name, binding, options]} =
      ast("step :greet, name <- input(:name), do: {:ok, %{name: name}}")

    parsed = InlineStep.parse!(binding, options, caller()).action
    {:<-, _, [variable, source]} = binding

    assert parsed.params_ast == {:%{}, [line: @source_line], [name: source]}
    assert parsed.pattern_ast == {:%{}, [line: @source_line], [name: variable]}
    assert parsed.body_ast == options[:do]
    assert parsed.options == []
    assert ValueParser.parse(parsed.params_ast) == {:ok, %{name: Ref.input(:name)}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "binding lists use named atom keys" do
    two = parse("step :sum, [left <- input(:left), right <- result(:load)], do: :ok")
    list = parse("step :sum, [a <- input(), b <- context(), _c <- value(3)], do: :ok")

    assert ValueParser.parse(two.params_ast) ==
             {:ok, %{left: Ref.input(:left), right: Ref.result(:load)}}

    assert Macro.to_string(two.pattern_ast) == "%{left: left, right: right}"

    assert ValueParser.parse(list.params_ast) ==
             {:ok, %{a: Ref.input([]), b: Ref.context([]), _c: 3}}

    assert Macro.to_string(list.pattern_ast) == "%{a: a, b: b, _c: _c}"
  end

  @tag obligation: "jido_action.inline.I2"
  test "explicit negative literals match direct construction and stored Flow execution" do
    owner = unique_owner("NegativeLiteral")

    compile_source("""
    defmodule #{inspect(owner)} do
      use Jido.Flow, name: "negative_literal"
      flow do
        step "echo", amount <- value(-1) do
          {:ok, %{amount: amount}, [:request]}
        end
        output result("echo")
      end
    end
    """)

    direct =
      Jido.Test.Flow.Builder.new!(
        name: "negative_literal",
        components: [
          Jido.Test.Flow.Component.step!(
            name: "echo",
            action: owner.step_action("echo"),
            params: %{amount: -1}
          )
        ],
        output: Ref.result("echo")
      )

    assert owner.flow() == direct
    assert {:ok, document, registry} = Jido.Test.Flow.GeneratedCodec.encode(direct)

    assert {:ok, restored} =
             Jido.Test.Flow.Codec.decode(JSON.decode!(JSON.encode!(document)), registry)

    assert restored == direct

    for target <- [owner, direct, restored] do
      assert Jido.Exec.run(target) == {:ok, %{amount: -1}, [:request]}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a sole map pattern retains nested matches and uses the whole source as params" do
    source = """
    step :read,
      %{"user" => %{name: name}, :kind => :person, 1 => {head, [first | rest]}} <- input(),
      do: {:ok, %{name: name, head: head, first: first, rest: rest}}
    """

    {:step, _, [_name, {:<-, _, [pattern, params]}, options]} = ast(source)
    parsed = parse(source)

    assert parsed.pattern_ast == pattern
    assert parsed.params_ast == params
    assert parsed.body_ast == options[:do]
    assert ValueParser.parse(parsed.params_ast) == {:ok, Ref.input([])}

    list = parse("step :read, [%{name: name} <- result(:load)], do: name")
    assert Macro.to_string(list.pattern_ast) == "%{name: name}"
    assert ValueParser.parse(list.params_ast) == {:ok, Ref.result(:load)}
  end

  @tag obligation: "jido_action.inline.I2"
  test "an explicit empty binding list produces empty params and a map pattern" do
    parsed = parse("step :ready, [], do: {:ok, %{ready: true}}")

    assert parsed.params_ast == {:%{}, [line: @source_line], []}
    assert parsed.pattern_ast == {:%{}, [line: @source_line], []}
  end

  @tag obligation: "jido_action.inline.I2"
  test "all header forms retain needs and meta options without body evaluation" do
    marker = :inline_body_ran
    body = quote do: send(self(), unquote(marker))

    option_sets = [
      [],
      [needs: [:first]],
      [meta: %{owner: :test}],
      [needs: [:first], meta: %{owner: :test}]
    ]

    for header <- [
          "name <- input()",
          "[left <- input(), right <- context()]",
          "[a <- input(), b <- context(), c <- 3]",
          "[]"
        ],
        options <- option_sets do
      {:step, _, [_name | arguments]} = ast("step :read, #{header}, do: :ok")
      arguments = List.replace_at(arguments, -1, options ++ [do: body])
      parsed = apply(InlineStep, :parse!, arguments ++ [caller()])

      assert parsed.component_options == options
      assert parsed.action.body_ast == body
    end

    refute_received ^marker
  end

  @tag obligation: "jido_action.inline.I2"
  test "needs headers keep nested after clauses as normal Elixir syntax" do
    source = """
    step :read, names <- input(:names), needs: [:load] do
      try do
        cleaner = fn name -> String.trim(name) end
        {:ok, %{names: Enum.map(names, cleaner)}}
      after
        cleanup()
      end
    end
    """

    {:step, _, [_name, _binding, _header_options, options]} = ast(source)
    parsed = parse_declaration(source)

    assert parsed.component_options == [needs: [:load]]
    assert parsed.action.body_ast == options[:do]
    assert Macro.to_string(parsed.action.body_ast) =~ "after"
  end

  @tag obligation: "jido_action.inline.I2"
  test "native do blocks keep separate header options for all binding forms" do
    for header <- [
          "name <- input()",
          "[left <- input(), right <- context()]",
          "[a <- input(), b <- context(), c <- 3]",
          "[]"
        ],
        options <- [
          "needs: [:load]",
          "meta: %{owner: :test}",
          "needs: [:load], meta: %{owner: :test}"
        ] do
      source = "step :read, #{header}, #{options} do\n  {:ok, %{}}\nend"
      {:step, _, arguments} = ast(source)
      parsed = parse_declaration(source)

      assert parsed.component_options == Enum.at(arguments, -2)
      assert Macro.to_string(parsed.action.body_ast) == "{:ok, %{}}"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "split header and body options reject duplicate fields" do
    assert_raise CompileError, ~r/duplicate inline Step field: :needs/, fn ->
      InlineStep.parse!([], [needs: [:one]], [needs: [:two], do: :ok], caller())
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline Step expressions can match validated parameters with case" do
    owner = unique_owner("ClauseStep")

    compile_source(
      flow_source(owner, """
      step "divide", operand <- input(:operand) do
        case operand do
          0 -> {:error, :zero}
          operand -> {:ok, %{value: 10 / operand}}
        end
      end
      """)
    )

    target = owner.step_action("divide")
    assert {:ok, %{value: 5.0}} = Jido.Exec.run(target, %{operand: 2})

    assert {:error, %Jido.Error.ExecutionError{message: "zero"}} =
             Jido.Exec.run(target, %{operand: 0})
  end

  @tag obligation: "jido_action.inline.I2"
  test "invalid bindings fail at the source declaration" do
    cases = [
      {"[name <- input(), name <- context()]", ~r/duplicate inline Step binding: :name/},
      {"[%{name: name} <- input(), other <- context()]", ~r/map pattern must be the only/},
      {"[%{name: name} <- input(), %{other: other} <- context()]", ~r/map pattern must be the only/},
      {"%User{name: name} <- input()", ~r/struct patterns are not supported/},
      {"^name <- input()", ~r/pinned variables are not supported/},
      {"%{name: ^name} <- input()", ~r/pinned variables are not supported/},
      {"(name when is_binary(name)) <- input()", ~r/guards are not supported/},
      {"_ <- input()", ~r/bare _ binding is not supported/},
      {"[name <- input(), :bad]", ~r/expected a binding/},
      {"[name: input()]", ~r/expected a binding/},
      {"[name <- input() | rest]", ~r/unsupported Flow expression/},
      {"{left, right} <- input()", ~r/named variable or a sole map pattern/},
      {"%{key => value} <- input()", ~r/map pattern keys must be literals/},
      {"%{name: name, name: other} <- input()", ~r/duplicate inline Step map key: :name/}
    ]

    for {header, message} <- cases do
      error =
        assert_raise CompileError, message, fn -> parse("step :read, #{header}, do: :ok") end

      assert error.file == @source_file
      assert error.line == @source_line
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "binding sources use direct Flow data without operations" do
    for header <- [
          "name <- String.trim(input(:name))",
          "[name <- input(), other <- name]",
          "name <- (input(:name) |> String.trim())",
          "name <- fn -> :ok end",
          "name <- %{duplicate: 1, duplicate: 2}",
          "name <- input(:name) <> \"!\"",
          "name <- %{nested: input(:name) <> \"!\"}"
        ] do
      error =
        assert_raise CompileError, ~r/inline Step binding source:.*Flow/s, fn ->
          parse("step :read, #{header}, do: :ok")
        end

      assert error.file == @source_file
      assert error.line == @source_line
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "source errors retain the offending expression line" do
    error =
      assert_raise CompileError, ~r/unsupported Flow expression/, fn ->
        parse("step :read,\n  name <-\n    String.trim(input(:name)),\n  do: name")
      end

    assert error.file == @source_file
    assert error.line == @source_line + 2
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline options reject explicit target fields, schema fields, and unknown fields" do
    for field <- [:action, :after, :params, :run, :schema, :output_schema, :unknown] do
      error =
        assert_raise CompileError,
                     "#{@source_file}:#{@source_line}: unsupported inline Step field: #{inspect(field)}; use only needs:, meta:, inline:, and do:",
                     fn ->
                       InlineStep.parse!(
                         ast("name <- input()"),
                         [{field, :invalid}, {:do, :ok}],
                         caller()
                       )
                     end

      assert error.file == @source_file
      assert error.line == @source_line
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "duplicate fields, missing bodies, and malformed options fail before parsing bindings" do
    for field <- [:needs, :meta, :do] do
      assert_raise CompileError, ~r/duplicate inline Step field/, fn ->
        InlineStep.parse!([], [{field, :first}, {field, :second}, {:do, :ok}], caller())
      end
    end

    assert_raise CompileError, ~r/inline Step requires a do block/, fn ->
      InlineStep.parse!([], [needs: [:first]], caller())
    end

    assert_raise CompileError, ~r/inline Step options must be a keyword list/, fn ->
      apply(InlineStep, :parse!, [[], :invalid, caller()])
    end

    assert parse("step :read, [], do: nil").body_ast == nil
  end

  @tag obligation: "jido_action.inline.I2"
  test "a second binding is not a Step options list" do
    assert_raise CompileError, ~r/inline Step options must be a keyword list/, fn ->
      InlineStep.parse!([ast("name <- input()")], ast("other <- context()"), [do: :ok], caller())
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "map patterns reject nested updates, guards, and dynamic keys" do
    for pattern <- [
          "%{name: (name when is_binary(name))}",
          "%{user: %{base | name: name}}",
          "%{user: %{key => name}}"
        ] do
      assert_raise CompileError, fn ->
        parse("step :read, #{pattern} <- input(), do: :ok")
      end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "map patterns retain normal nested structs, binary matches, aliases, and matches" do
    pattern =
      "%{uri: %URI{path: path}, pair: {first, second, _}, bytes: <<head::integer, tail::binary>>, value: value = [item | _], module: String, prefix: \"x\" <> suffix}"

    source = "step :read, #{pattern} <- input(), do: :ok"
    {:step, _, [_name, {:<-, _, [pattern_ast, _]}, _]} = ast(source)
    parsed = parse(source)
    assert parsed.pattern_ast == pattern_ast
  end

  @tag obligation: "jido_action.inline.I2"
  test "map patterns retain binary size references and signed literal keys" do
    source =
      "step :read, %{-1 => name, data: <<width, body::binary-size(width * 8)>>} <- input(), do: :ok"

    {:step, _, [_name, {:<-, _, [pattern_ast, _]}, _]} = ast(source)

    assert parse(source).pattern_ast == pattern_ast
  end

  @tag obligation: "jido_action.inline.I2"
  test "map patterns reject equivalent signed literal keys" do
    for pattern <- [
          "%{-1 => first,\n  -1 => second}",
          "%{+1 => first, 1 => second}",
          "%{1 => first, +1 => second}"
        ] do
      error =
        assert_raise CompileError, ~r/duplicate inline Step map key/, fn ->
          parse("step :read, #{pattern} <- input(), do: :ok")
        end

      assert error.file == @source_file
      assert error.line == @source_line
    end
  end

  defp parse(source) do
    parse_declaration(source).action
  end

  defp parse_declaration(source) do
    {:step, _, [_name | arguments]} = ast(source)
    apply(InlineStep, :parse!, arguments ++ [caller()])
  end

  defp unique_owner(prefix),
    do: Module.concat(__MODULE__, "#{prefix}#{System.unique_integer([:positive])}")

  defp flow_source(owner, declarations, before_code \\ "", after_code \\ "") do
    """
    defmodule #{inspect(owner)} do
      use Jido.Flow, name: "inline_test"
      #{before_code}
      flow do
        #{declarations}
        output(%{})
      end
      #{after_code}
    end
    """
  end

  defp generated_identity(owner, name) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({owner, [host: Jido.Flow, step: name, role: :action]})
      )
      |> Base.encode16(case: :lower)

    target = Module.concat(Jido.Action.Generated.Inline, "A" <> digest)
    {target, target}
  end

  defp definition_source(visibility, function, args) do
    definition = {visibility, [], [{function, [], args}, [do: :user_clause]]}

    "Code.eval_quoted(#{inspect(definition, limit: :infinity, printable_limit: :infinity, width: :infinity)}, [], __ENV__)"
  end

  defp generated_modules do
    for {module, _} <- :code.all_loaded(),
        String.starts_with?(Atom.to_string(module), "Elixir.Jido.Action.Generated.Inline."),
        into: MapSet.new(),
        do: module
  end

  defp ast(source), do: Code.string_to_quoted!(source, line: @source_line, columns: true)
  defp caller, do: %{__ENV__ | file: @source_file, line: @source_line}

  defp call_params(%{call: %{params: params}}), do: params

  defp canonical_data?(value) when is_map(value) do
    not is_struct(value, Macro.Env) and
      Enum.all?(Map.to_list(value), fn {key, item} ->
        canonical_data?(key) and canonical_data?(item)
      end)
  end

  defp canonical_data?(value) when is_list(value), do: Enum.all?(value, &canonical_data?/1)
  defp canonical_data?(value) when is_tuple(value), do: false
  defp canonical_data?(value), do: not is_function(value)

  defp diagnostic_line(%{position: {line, _column}}), do: line
  defp diagnostic_line(%{position: line}), do: line

  defp compile_source(source, file \\ "inline_compile.ex") do
    loaded = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    try do
      Code.compile_string(source, file)
    after
      owned =
        for {module, _} <- :code.all_loaded(),
            not MapSet.member?(loaded, module),
            String.starts_with?(Atom.to_string(module), [
              "Elixir.Jido.Flow.DSL.InlineStepTest.",
              "Elixir.Jido.Action.Generated.Inline."
            ]),
            do: module

      on_exit(fn ->
        Enum.each(owned, fn module ->
          :code.purge(module)
          :code.delete(module)
        end)
      end)
    end
  end
end
