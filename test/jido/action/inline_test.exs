defmodule Jido.Action.InlineTest do
  use Covenant.Case, component: "jido_action.inline", async: false

  alias Jido.Action.Inline

  defmodule Host do
    defmacro action_zero_import(path, pattern, options) do
      parsed = Jido.Action.Inline.parse_callback!(pattern, options, __CALLER__)

      compiled =
        Jido.Action.Inline.compile!(path, parsed, __CALLER__,
          default_name: "zero_import",
          remove_imports: [{__MODULE__, [helper_marker: 0]}]
        )

      compiled.declaration_ast
    end

    defmacro action_named(path, pattern, options) do
      parsed = Jido.Action.Inline.parse_callback!(pattern, options, __CALLER__)
      compiled = Jido.Action.Inline.compile!(path, parsed, __CALLER__)
      compiled.declaration_ast
    end

    defmacro action(path, mode, header, options) do
      compile_declaration(path, mode, header, options, __CALLER__)
    end

    defmacro action(path, mode, header, options, body_options) do
      compile_declaration(path, mode, header, options ++ body_options, __CALLER__)
    end

    defp compile_declaration(path, mode, header, options, caller) do
      parsed =
        case mode do
          :bound -> Jido.Action.Inline.parse_bound!(header, options, caller)
          :callback -> Jido.Action.Inline.parse_callback!(header, options, caller)
        end

      # This host accepts literal sources only. It owns source validation.
      if parsed.mode == :bound and not Macro.quoted_literal?(parsed.params_ast) do
        raise CompileError,
          file: caller.file,
          line: caller.line,
          description: "test host requires literal sources"
      end

      compiled =
        Jido.Action.Inline.compile!(path, parsed, caller,
          default_name: "test_action",
          remove_imports: [{__MODULE__, [action: 4]}, {__MODULE__, [action: 5]}]
        )

      quote do
        unquote(compiled.declaration_ast)
        @last_inline_target unquote(compiled.target_ast)
      end
    end

    def helper_marker, do: :import_retained

    defmacro decorate(value) do
      quote do: "[" <> unquote(value) <> "]"
    end
  end

  defmodule Hooks do
    def __on_definition__(env, _kind, name, _args, _guards, _body) do
      send(self(), {:host_definition, env.module, name})
    end

    defmacro __before_compile__(env) do
      send(self(), {:host_before_compile, env.module})
      quote do: def(host_hook_value(), do: :host_hook)
    end
  end

  defmodule Names do
    def next_name do
      send(self(), :name_evaluated)
      "expression"
    end

    def schema do
      send(self(), :schema_evaluated)
      Jido.Joi.object(%{value: Jido.Joi.integer()})
    end
  end

  setup do
    loaded = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    on_exit(fn ->
      for {module, _} <- :code.all_loaded(),
          not MapSet.member?(loaded, module),
          String.starts_with?(Atom.to_string(module), [
            "Elixir.Jido.Action.InlineTest.",
            "Elixir.Jido.Action.Generated.Inline."
          ]) do
        :code.purge(module)
        :code.delete(module)
      end
    end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "the public facade creates an ordinary Action without Flow state" do
    owner = unique_owner("Plain")

    compile_source(owner, """
    action [host: :test, declaration: "increment", role: :action], :bound, value <- 1 do
      {:ok, %{value: value + 1, owner: __MODULE__}}
    end
    """)

    target = Inline.target!(owner, path("increment"))
    assert Jido.Joi.Schema.kind(target.schema()) == :map
    assert Jido.Joi.Schema.kind(target.output_schema()) == :map
    assert target.name() == "test_action"

    assert {:ok, %Jido.Instruction{kind: :action, target: ^target}} =
             Jido.Instruction.resolve(target)

    assert target.run(%{value: 2}, %{}) == {:ok, %{value: 3, owner: owner}}
  end

  @tag obligation: "jido_action.inline.I1"
  test "bound parsing returns host source AST without evaluating or validating it" do
    source = quote line: 40, do: value <- unknown_host_source()
    parsed = Inline.parse_bound!(source, [do: quote(do: {:ok, %{value: value}})], env())
    assert parsed.mode == :bound
    assert Macro.to_string(parsed.params_ast) == "%{value: unknown_host_source()}"
    assert Macro.to_string(parsed.pattern_ast) == "%{value: value}"
  end

  @tag obligation: "jido_action.inline.I1"
  test "bound headers preserve the current source and pattern shapes" do
    for {source, params, pattern} <- [
          {"value <- 1", "%{value: 1}", "%{value: value}"},
          {"[left <- 1, right <- 2]", "%{left: 1, right: 2}", "%{left: left, right: right}"},
          {"%{value: value} <- host_ref()", "host_ref()", "%{value: value}"},
          {"[]", "%{}", "%{}"}
        ] do
      parsed = Inline.parse_bound!(quoted(source), [do: nil], env())
      assert Macro.to_string(parsed.params_ast) == params
      assert Macro.to_string(parsed.pattern_ast) == pattern

      if source != "%{value: value} <- host_ref()" do
        assert elem(parsed.params_ast, 1)[:line] == 40
        assert elem(parsed.pattern_ast, 1)[:line] == 40
      end
    end
  end

  @tag obligation: "jido_action.inline.I1"
  test "callback headers receive parameters directly without a source map" do
    for pattern <- ["params", "%{value: value, nested: %{item: item}}"] do
      parsed = Inline.parse_callback!(quoted(pattern), [do: nil], env())
      assert parsed.mode == :callback
      assert parsed.params_ast == nil
      assert Macro.to_string(parsed.pattern_ast) == pattern
    end
  end

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "header errors preserve the source location" do
    for {mode, source, message} <- [
          {:bound, "[value <- 1, value <- 2]", "duplicate inline Action binding"},
          {:bound, "[%{value: value} <- %{}, other <- 1]", "map pattern must be the only"},
          {:bound, "_ <- 1", "bare _"},
          {:bound, "42", "expected a binding in the form"},
          {:bound, "42 <- 1", "requires a named variable"},
          {:bound, "_() <- 1", "requires a named variable"},
          {:bound, "%{old | replacement: new} <- %{}", "map updates are not supported"},
          {:bound, "^value <- 1", "pinned variables"},
          {:bound, "(value when is_map(value)) <- %{}", "guards"},
          {:bound, "%URI{} <- %{}", "top-level struct"},
          {:bound, "%{key => value} <- %{}", "keys must be literals"},
          {:bound, "%{value: a, value: b} <- %{}", "duplicate inline Action map key"},
          {:bound, "%{value: ^value} <- %{}", "pinned variables"},
          {:callback, "params <- input()", "callback requires"},
          {:callback, "[params <- context()]", "callback requires"},
          {:callback, "[]", "callback requires"},
          {:callback, "_", "bare _"},
          {:callback, "_()", "callback requires a named variable"},
          {:callback, "%URI{}", "top-level struct"}
        ] do
      error =
        assert_raise CompileError, fn ->
          parse(mode, quoted(source), do: nil)
        end

      assert error.description =~ message
      assert error.file == "inline_header.ex"
      assert error.line == 40
    end
  end

  @tag obligation: "jido_action.inline.I1"
  test "Action options and context reject ambiguous declarations" do
    for {header, options, message} <- [
          {"params", [], "requires a do block"},
          {"params", [do: nil, do: nil], "duplicate inline Action option"},
          {"params", [do: nil, unknown: 1], "unsupported inline Action option"},
          {"params", [do: nil, name: "first", name: "second"], "duplicate inline Action option"},
          {"params", [do: nil, context: quoted("_")], "context must be a named variable"},
          {"params", [do: nil, context: quoted("%{value: value}")], "context must be a named variable"},
          {"params", [do: nil, context: quoted("params")], "context variable collides"},
          {"%{nested: %{ctx: ctx}}", [do: nil, context: quoted("ctx")], "context variable collides"}
        ] do
      error =
        assert_raise CompileError, fn ->
          Inline.parse_callback!(quoted(header), options, env())
        end

      assert error.description =~ message
      assert error.file == "inline_header.ex"
      assert error.line == 40
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "bodies retain lexical scope, explicit context, private helpers and declaration attributes" do
    owner = unique_owner("Lexical")

    compile_source(owner, """
    alias String, as: Text
    @prefix "first"
    action [host: :test, declaration: @prefix, role: :action], :callback, %{value: value},
      context: ctx do
      {:ok, %{value: decorate(private_helper(Text.trim(value))), context: ctx,
              owner: __MODULE__, prefix: @prefix, imported: helper_marker(),
              local: action(1, 2, 3, 4)}}
    end
    @prefix "second"
    action [host: :test, declaration: @prefix, role: :action], :bound, [] do
      {:ok, %{prefix: @prefix}}
    end
    defp private_helper(value), do: Text.upcase(value)
    defp action(a, b, c, d), do: a + b + c + d
    def last_target, do: @last_inline_target
    """)

    context = %{secret: make_ref()}

    assert Inline.target!(owner, path("first")).run(%{value: " Ada "}, context) ==
             {:ok,
              %{
                value: "[ADA]",
                context: context,
                owner: owner,
                prefix: "first",
                imported: :import_retained,
                local: 10
              }}

    second = Inline.target!(owner, path("second"))
    assert second.run(%{}, %{}) == {:ok, %{prefix: "second"}}
    assert owner.last_target() == second
  end

  @tag obligation: "jido_action.inline.I2"
  test "metadata and schemas evaluate in the declaration environment and use normal Action validation" do
    owner = unique_owner("Schema")

    compile_source(owner, """
    alias Jido.Joi, as: Shape
    @input_schema Shape.object(%{value: Shape.integer() |> Shape.default(4)})
    @description "typed callback"
    action [host: :test, declaration: "typed", role: :action], :callback, %{value: value},
      name: "public_name", description: @description, schema: @input_schema,
      output_schema: Shape.object(%{value: Shape.integer()}), context: ctx do
      send(ctx.owner, :typed_body)
      {:ok, %{value: value + ctx.add}}
    end
    """)

    target = Inline.target!(owner, path("typed"))
    assert target.name() == "public_name"
    assert target.description() == "typed callback"
    assert {:ok, %{value: 4}} = target.validate_params(%{extra: true})
    refute_received :typed_body

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(target, %{value: "bad"}, %{owner: self(), add: 1})

    refute_received :typed_body
    assert Jido.Exec.run(target, %{}, %{owner: self(), add: 1}) == {:ok, %{value: 5}}
    assert_received :typed_body

    assert {:error, %Jido.Error.ValidationError{}} =
             target.validate_output(%{value: "bad"})
  end

  @tag obligation: "jido_action.inline.I2"
  test "bound Actions keep context out of params and evaluate configuration expressions once" do
    owner = unique_owner("BoundSchema")

    compile_source(owner, """
    action [host: :test, declaration: "bound", role: :action], :bound, value <- 1,
      name: #{inspect(Names)}.next_name(), schema: #{inspect(Names)}.schema(), context: ctx do
      {:ok, %{value: value, prefix: ctx.prefix}}
    end
    """)

    assert_received :name_evaluated
    refute_received :name_evaluated
    assert_received :schema_evaluated
    refute_received :schema_evaluated
    target = Inline.target!(owner, path("bound"))
    assert target.name() == "expression"
    assert target.validate_params(%{value: 4}) == {:ok, %{value: 4}}

    assert Jido.Exec.run(target, %{value: 4}, %{prefix: "new"}) ==
             {:ok, %{value: 4, prefix: "new"}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "invalid metadata or static schema cannot start replacement of an existing wrapper" do
    for option <- [
          "name: \"\"",
          "name: :bad",
          "description: 42",
          "schema: :invalid",
          "schema: Jido.Joi.integer()",
          "output_schema: Jido.Joi.integer()",
          "schema: Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.refine(fn _ -> :ok end)})"
        ] do
      owner = unique_owner("InvalidConfig")

      declaration =
        ~s(action [host: :test, declaration: "same", role: :action], :bound, [], do: {:ok, %{version: 1}})

      compile_source(owner, declaration)
      target = Inline.target!(owner, path("same"))
      original_md5 = target.module_info(:md5)

      replacement =
        ~s(action [host: :test, declaration: "same", role: :action], :bound, [], #{option}, do: {:ok, %{version: 2}})

      {_error, diagnostics} =
        Code.with_diagnostics(fn ->
          assert_raise CompileError, fn -> compile_source(owner, replacement) end
        end)

      # An owner redefinition warning is expected. A target warning means the
      # compiler started replacing it before it checked Action configuration.
      refute Enum.any?(diagnostics, &(&1.message =~ "redefining module #{inspect(target)}"))
      assert target.name() == "test_action"
      assert target.module_info(:md5) == original_md5
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "setup is idempotent and retains host hooks in either registration order" do
    for position <- [:before, :after] do
      owner = unique_owner("Hooks")
      hooks = "@on_definition #{inspect(Hooks)}\n@before_compile #{inspect(Hooks)}"
      {before, after_setup} = if position == :before, do: {hooks, ""}, else: {"", hooks}

      compile_source(
        owner,
        """
        #{after_setup}
        action [host: :test, declaration: "first", role: :action], :bound, [], do: {:ok, %{first: true}}
        use Jido.Action.Inline
        :ok = Jido.Action.Inline.setup!(__ENV__)
        action [host: :test, declaration: "second", role: :action], :bound, [], do: {:ok, %{second: true}}
        send(self(), {:hook_counts,
          Enum.count(Module.get_attribute(__MODULE__, :on_definition), fn {module, _} -> module == Jido.Action.Inline.Owner end),
          Enum.count(Module.get_attribute(__MODULE__, :before_compile), fn {module, _} -> module == Jido.Action.Inline.Owner end)})
        """,
        before
      )

      assert Inline.target!(owner, path("first")).run(%{}, %{}) == {:ok, %{first: true}}
      assert Inline.target!(owner, path("second")).run(%{}, %{}) == {:ok, %{second: true}}
      assert owner.host_hook_value() == :host_hook
      assert_received {:hook_counts, 1, 1}
      assert_received {:host_before_compile, ^owner}
      refute_received {:host_before_compile, ^owner}
      assert_received {:host_definition, ^owner, :__jido_inline_actions__}
    end
  end

  @tag obligation: "jido_action.inline.I3"
  test "target identity uses the owner and complete typed path, not metadata" do
    paths = [
      [host: :test, choice: "first", option: "otherwise", role: :action],
      [host: :test, choice: "first", fallback: "otherwise", role: :action],
      [host: :test, choice: "second", option: "otherwise", role: :action],
      [host: :test, declaration: "invoke", role: :decision],
      [host: :test, declaration: "invoke", role: :expander],
      [host: Jido.Flow, step: "same", role: :action],
      [host: Jido.Actor, route: "same", role: :action],
      [host: :test, declaration: "1", role: :action],
      [host: :test, declaration: 1, role: :action],
      [host: :test, declaration: :"1", role: :action]
    ]

    owners = for _ <- 1..2, do: unique_owner("Identity")

    declarations =
      Enum.map_join(paths, "\n", fn path ->
        "action #{inspect(path)}, :callback, params, name: \"shared_name\", do: {:ok, params}"
      end)

    for owner <- owners, do: compile_source(owner, declarations)
    targets = for owner <- owners, path <- paths, do: Inline.target!(owner, path)
    assert length(Enum.uniq(targets)) == length(owners) * length(paths)
    assert Enum.all?(targets, &(byte_size(Atom.to_string(&1)) < 128))
    assert Enum.all?(targets, &(&1.name() == "shared_name"))
  end

  @tag obligation: "jido_action.inline.I3"
  test "compilation does not intern a separate atom for the owner callback" do
    owner = unique_owner("CallbackAtom")
    declaration_path = path("bounded")

    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({owner, declaration_path}))
      |> Base.encode16(case: :lower)

    callback_name = "__jido_inline_action_" <> digest

    assert_raise ArgumentError, fn -> String.to_existing_atom(callback_name) end

    compile_source(
      owner,
      ~s(action #{inspect(declaration_path)}, :bound, [], do: {:ok, %{bounded: true}})
    )

    assert_raise ArgumentError, fn -> String.to_existing_atom(callback_name) end
    assert Inline.target!(owner, declaration_path).run(%{}, %{}) == {:ok, %{bounded: true}}
  end

  @tag obligation: ["jido_action.inline.I2", "jido_action.inline.I3"]
  test "duplicate and foreign identities fail before target replacement" do
    owner = unique_owner("Duplicate")

    source =
      ~s(action [host: :test, declaration: "same", role: :action], :bound, [], do: {:ok, %{}})

    assert_raise CompileError, ~r/duplicate inline Action identity/, fn ->
      compile_source(owner, source <> "\n" <> source)
    end

    foreign_owner = unique_owner("Foreign")
    {target, _} = generated_identity(foreign_owner, path("same"))
    Code.compile_string("defmodule #{inspect(target)}, do: def(untouched(), do: :foreign)")

    assert_raise CompileError, ~r/generated inline Action module.*already belongs/, fn ->
      compile_source(foreign_owner, source)
    end

    assert target.untouched() == :foreign
  end

  @tag obligation: "jido_action.inline.I3"
  test "names evaluate once and false compile branches emit no target or index entry" do
    owner = unique_owner("Evaluation")

    compile_source(owner, """
    if false do
      action [host: :test, declaration: "skipped", role: :action], :bound, [], do: {:ok, %{}}
    end
    action [host: :test, declaration: #{inspect(Names)}.next_name(), role: :action], :bound, [], do: {:ok, %{}}
    """)

    assert_received :name_evaluated
    refute_received :name_evaluated
    assert is_atom(Inline.target!(owner, path("expression")))
    assert_raise ArgumentError, fn -> Inline.target!(owner, path("skipped")) end
    {skipped, _} = generated_identity(owner, path("skipped"))
    refute Code.ensure_loaded?(skipped)
  end

  @tag obligation: "jido_action.inline.I3"
  test "lookup is inert and unknown paths do not create atoms" do
    owner = unique_owner("Lookup")

    compile_source(owner, """
    action [host: :test, declaration: "work", role: :action], :callback, params, context: ctx do
      send(ctx.owner, :inline_work)
      {:ok, params}
    end
    """)

    target = Inline.target!(owner, path("work"))
    assert {:ok, %{}} = target.validate_params(%{})
    refute_received :inline_work
    names = for i <- 1..50, do: "unknown_#{i}_#{System.unique_integer([:positive])}"

    lookup = fn ->
      for name <- names,
          do: assert_raise(ArgumentError, fn -> Inline.target!(owner, path(name)) end)
    end

    lookup.()
    count = :erlang.system_info(:atom_count)
    for _ <- 1..3, do: lookup.()
    assert :erlang.system_info(:atom_count) == count
    for name <- names, do: assert_raise(ArgumentError, fn -> String.to_existing_atom(name) end)
    assert target.run(%{new: true}, %{owner: self()}) == {:ok, %{new: true}}
    assert_received :inline_work
  end

  @tag obligation: "jido_action.inline.I3"
  test "compilation requires an open owner and lookup requires a completed owner" do
    parsed = Inline.parse_bound!([], [do: nil], env())

    assert_raise CompileError, ~r/requires a compiling owner/, fn ->
      Inline.compile!(Macro.escape(path("outside")), parsed, env(), default_name: "outside")
    end

    assert_raise CompileError, ~r/requires a compiling owner/, fn -> Inline.setup!(env()) end
    owner = unique_owner("OpenLookup")

    assert_raise ArgumentError, ~r/only after the owner compiles/, fn ->
      compile_source(owner, "Jido.Action.Inline.target!(__MODULE__, #{inspect(path("missing"))})")
    end
  end

  @tag obligation: "jido_action.inline.I1"
  test "host source rejection occurs before target creation and a corrected declaration can compile" do
    owner = unique_owner("SourceRepair")

    assert_raise CompileError, ~r/test host requires literal sources/, fn ->
      compile_source(
        owner,
        ~s|action [host: :test, declaration: "same", role: :action], :bound, value <- unknown_source(), do: {:ok, %{value: value}}|
      )
    end

    {target, _} = generated_identity(owner, path("same"))
    refute Code.ensure_loaded?(target)

    compile_source(
      owner,
      ~s(action [host: :test, declaration: "same", role: :action], :bound, value <- 1, do: {:ok, %{value: value}})
    )

    assert Inline.target!(owner, path("same")) == target
    assert target.run(%{value: 3}, %{}) == {:ok, %{value: 3}}
  end

  @tag obligation: "jido_action.inline.I1"
  test "invalid paths and option lists have the documented error types" do
    for invalid <- [
          nil,
          :name,
          [],
          [host: :test, role: :action],
          [host: :test, declaration: %{}, role: :action],
          [{:host, :test}, {"declaration", "x"}, {:role, :action}],
          [{:host, :test}, {:declaration, "x"}, {:role, :action} | :invalid]
        ] do
      assert_raise ArgumentError, fn -> Inline.target!(__MODULE__, invalid) end
      owner = unique_owner("InvalidPath")

      assert_raise CompileError, ~r/identity must be a typed path/, fn ->
        compile_source(owner, "action #{inspect(invalid)}, :bound, [], do: {:ok, %{}}")
      end
    end

    for options <- [nil, %{}, [{:do, nil} | :invalid]] do
      assert_raise CompileError, ~r/options must be a keyword list/, fn ->
        Inline.parse_bound!([], options, env())
      end
    end
  end

  @tag obligation: "jido_action.inline.I1"
  test "malformed compiler options and import-removal lists have source errors" do
    parsed = Inline.parse_bound!([], [do: nil], env())

    for {options, message} <- [
          {[identity: {__MODULE__, :identity}], "unsupported inline Action compiler: :identity"},
          {[default_name: "one", default_name: "two"], "duplicate inline Action compiler: :default_name"}
        ] do
      error =
        assert_raise CompileError, fn ->
          Inline.compile!(Macro.escape(path("bad")), parsed, env(), options)
        end

      assert error.description == message
    end

    for removals <- [
          :all,
          [String],
          [{nil, []}],
          [{"String", []}],
          [{String, [upcase: 0.5]}],
          [{String, :all}],
          [{String, [upcase: -1]}],
          [{String, [upcase: 1]} | :bad]
        ] do
      owner = unique_owner("BadImports")

      source = """
      defmodule #{inspect(owner)} do
        use Jido.Action.Inline
        parsed = Jido.Action.Inline.parse_bound!([], [do: nil], __ENV__)
        Jido.Action.Inline.compile!([], parsed, __ENV__, default_name: "bad", remove_imports: #{inspect(removals)})
      end
      """

      error =
        assert_raise CompileError, ~r/remove_imports must be/, fn ->
          Code.compile_string(source, "inline_imports.ex")
        end

      assert error.file == "inline_imports.ex"
      assert error.line == 4
    end
  end

  @tag obligation: "jido_action.inline.I1"
  test "an improper bound header reports a source error" do
    assert_raise CompileError, ~r/bindings must be a proper list/, fn ->
      Inline.parse_bound!([quoted("value <- 1") | :bad], [do: nil], env())
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "owner body and index functions reject user clauses and default-argument arities" do
    for kind <- [:index, :body], position <- [:before, :after], defaults <- [0, 1] do
      owner = unique_owner("Reserved")
      {_target, body_function} = generated_identity(owner, path("same"))

      {function, required} =
        if kind == :index, do: {:__jido_inline_actions__, 0}, else: {body_function, 2}

      args =
        List.duplicate({:_, [], nil}, required) ++
          List.duplicate({:\\, [], [{:_, [], nil}, []]}, defaults)

      definition = {:def, [], [{function, [], args}, [do: :user]]}

      clause =
        "Code.eval_quoted(#{inspect(definition, limit: :infinity)}, [], __ENV__)"

      declaration =
        ~s(action [host: :test, declaration: "same", role: :action], :bound, [], do: {:ok, %{}})

      {before, after_code} = if position == :before, do: {clause, ""}, else: {"", clause}

      error =
        assert_raise CompileError, ~r/reserved inline Action function/, fn ->
          compile_source(owner, declaration <> "\n" <> after_code, before)
        end

      assert error.file == "inline_compile.ex"
      assert error.description =~ "#{function}/#{required}"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "warnings, compile failures and runtime stacktraces retain the body source" do
    warning_owner = unique_owner("Warning")

    {_modules, diagnostics} =
      Code.with_diagnostics(fn ->
        compile_source(warning_owner, """
        action [host: :test, declaration: "unused", role: :action], :bound, [] do
          unused_local = 1
          {:ok, %{}}
        end
        """)
      end)

    assert Enum.any?(diagnostics, &(&1.message =~ "unused_local" and diagnostic_line(&1) == 6))

    bad_owner = unique_owner("Undefined")

    {_error, diagnostics} =
      Code.with_diagnostics(fn ->
        assert_raise CompileError, fn ->
          compile_source(bad_owner, """
          action [host: :test, declaration: "bad", role: :action], :bound, [] do
            missing_body_helper()
          end
          """)
        end
      end)

    assert Enum.any?(
             diagnostics,
             &(&1.message =~ "undefined function missing_body_helper/0" and
                 Path.basename(&1.file) == "inline_compile.ex" and diagnostic_line(&1) == 6)
           )

    crash_owner = unique_owner("Crash")

    compile_source(crash_owner, """
    action [host: :test, declaration: "raise", role: :action], :bound, [] do
      raise "body failure"
    end
    """)

    target = Inline.target!(crash_owner, path("raise"))

    stacktrace =
      try do
        target.run(%{}, %{})
      rescue
        RuntimeError -> __STACKTRACE__
      end

    assert Enum.any?(stacktrace, fn
             {^crash_owner, _function, 2, location} ->
               location[:file] == ~c"inline_compile.ex" and location[:line] == 6

             _ ->
               false
           end)
  end

  @tag obligation: "jido_action.inline.I1"
  test "callback clause bodies compile to several owner-function heads" do
    owner = unique_owner("CallbackClauses")

    compile_source(owner, """
    action [host: :test, declaration: "divide", role: :action], :callback, nil,
      [schema: Jido.Joi.object(%{operand: Jido.Joi.number()}), context: ctx] do
      %{operand: operand} when operand == 0 ->
        send(ctx.observer, :zero)
        {:error, :zero}

      %{operand: operand} when operand < ctx.minimum ->
        send(ctx.observer, :negative)
        {:error, :negative}

      %{operand: operand} ->
        send(ctx.observer, :ok)
        {:ok, %{value: 10 / operand}}
    end
    """)

    target = Inline.target!(owner, path("divide"))
    context = %{observer: self(), minimum: 0}
    assert target.run(%{operand: 0}, context) == {:error, :zero}
    assert_received :zero
    assert target.run(%{operand: 0.0}, context) == {:error, :zero}
    assert_received :zero
    assert target.run(%{operand: -2}, context) == {:error, :negative}
    assert_received :negative
    assert {:ok, %{value: 5.0}} = target.run(%{operand: 2}, context)
    assert_received :ok
    assert {:ok, %{value: 5.0}} = Jido.Exec.run(target, %{operand: 2}, context)
    assert_received :ok

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Exec.run(target, %{operand: "2"}, context)

    refute_received :ok
  end

  @tag obligation: "jido_action.inline.I1"
  test "bound clause bodies match the resolved parameter map" do
    owner = unique_owner("BoundClauses")

    compile_source(owner, """
    action [host: :test, declaration: "divide", role: :action], :bound, operand <- 10 do
      %{operand: 0} -> {:error, :zero}
      %{operand: operand} -> {:ok, %{value: 100 / operand}}
    end
    """)

    target = Inline.target!(owner, path("divide"))
    assert target.run(%{operand: 0}, %{}) == {:error, :zero}
    assert {:ok, %{value: 25.0}} = target.run(%{operand: 4}, %{})
  end

  @tag obligation: "jido_action.inline.I2"
  test "clause definitions retain their source line" do
    owner = unique_owner("ClauseLine")

    compile_source(owner, """
    action [host: :test, declaration: "line", role: :action], :callback, nil do
      %{value: value} when is_integer(value) -> {:ok, %{value: value}}
    end
    """)

    target = Inline.target!(owner, path("line"))

    stacktrace =
      try do
        target.run(%{}, %{})
      rescue
        FunctionClauseError -> __STACKTRACE__
      end

    assert Enum.any?(stacktrace, fn
             {^owner, _function, arguments, location} when length(arguments) == 2 ->
               location[:line] == 6

             _ ->
               false
           end)
  end

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "clause-body parse errors preserve the source location" do
    clauses = case_clauses("%{operand: 0} -> :zero\n%{operand: operand} -> :ok")

    parsed = Inline.parse_callback!(nil, [do: clauses], env())
    assert parsed.mode == :callback
    assert parsed.pattern_ast == nil
    assert length(parsed.clauses) == 2

    bound = Inline.parse_bound!(quoted("operand <- 1"), [do: clauses], env())
    assert bound.mode == :bound
    assert is_list(bound.clauses)
    assert bound.pattern_ast == quoted("%{operand: operand}")

    [arrow] = case_clauses("%{operand: 0} -> :zero")
    mixed = {:__block__, [line: 40], [arrow, :ok]}

    for {mode, header, options, message} <- [
          {:callback, quoted("%{operand: operand}"), [do: clauses], "clause body cannot include a header pattern"},
          {:callback, nil, [do: mixed], "cannot mix clause heads with an expression body"},
          {:callback, nil, [do: case_clauses("{1, 2} -> :ok")], "named variable, `_`, or a map pattern"},
          {:callback, nil, [do: case_clauses("_() -> :ok")], "named variable, `_`, or a map pattern"},
          {:bound, quoted("operand <- 1"), [do: case_clauses("%URI{} -> :ok")], "struct patterns"},
          {:callback, nil, [do: case_clauses("%{ctx: ctx} -> :ok\n_ -> :other"), context: quoted("ctx")],
           "context variable collides"},
          {:callback, nil, [do: case_clauses("%{value: ^expected} -> :ok")], "pinned variables"}
        ] do
      error =
        assert_raise CompileError, fn ->
          parse(mode, header, options)
        end

      assert error.description =~ message
      assert error.file == "inline_header.ex"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "the three-argument compiler uses explicit Action metadata" do
    owner = unique_owner("NamedCompiler")

    compile_source(owner, """
    action_named [host: :test, declaration: "named", role: :action], params,
      name: "explicit_name", do: {:ok, params}
    """)

    target = Inline.target!(owner, path("named"))
    assert target.name() == "explicit_name"
    assert Jido.Exec.run(target, %{value: 1}) == {:ok, %{value: 1}}
  end

  @tag obligation: "jido_action.inline.I1"
  test "single and block clause ASTs keep their patterns guards and bodies" do
    [arrow] = case_clauses("%{value: value} when is_integer(value) -> {:ok, value}")
    {:->, _, [[{:when, _, [pattern, guard]}], body]} = arrow

    for ast <- [arrow, [arrow], {:__block__, [], [arrow]}] do
      parsed = Inline.parse_callback!(nil, [do: ast], env())
      assert parsed.clauses == [{pattern, guard, body}]
    end

    parsed = Inline.parse_callback!(quoted("params"), [do: {:__block__, [], []}], env())
    assert parsed.clauses == nil

    for head <- [
          "first, second -> :both",
          "() -> :none",
          "first, is_map(first) when true -> :both"
        ] do
      error =
        assert_raise CompileError, fn ->
          Inline.parse_callback!(nil, [do: case_clauses(head)], env())
        end

      assert error.description == "inline Action clause requires one parameter pattern"
      assert error.line == 41
    end

    error =
      assert_raise CompileError, fn ->
        Inline.parse_callback!(nil, [do: case_clauses("first,\nsecond -> :both")], env())
      end

    assert error.description == "inline Action clause requires one parameter pattern"
    assert error.line == 41
  end

  @tag obligation: "jido_action.inline.I1"
  test "signed map keys retain distinct values and reject duplicate or executable keys" do
    for source <- ["%{-1 => left, nil => right}", "%{+1 => left, nil => right}"] do
      parsed = Inline.parse_callback!(quoted(source), [do: nil], env())
      assert parsed.pattern_ast == quoted(source)
    end

    for source <- ["%{+1 => left, 1 => right}", "%{-1 => left, -1 => right}"] do
      assert_raise CompileError, ~r/duplicate inline Action map key/, fn ->
        Inline.parse_callback!(quoted(source), [do: nil], env())
      end
    end

    for source <- ["%{-unknown => value}", "%{+unknown => value}", "%{+:invalid => value}"] do
      assert_raise CompileError, ~r/map pattern keys must be literals/, fn ->
        Inline.parse_callback!(quoted(source), [do: nil], env())
      end
    end
  end

  @tag obligation: ["jido_action.inline.I1", "jido_action.inline.I2"]
  test "guarded clauses keep one parameter and native repeated when guards" do
    owner = unique_owner("GuardedHead")

    error =
      assert_raise CompileError, fn ->
        compile_source(owner, """
        action [host: :test, declaration: "invalid", role: :action], :callback, nil do
          params, is_map(params) when true -> {:ok, params}
        end
        """)
      end

    assert error.description == "inline Action clause requires one parameter pattern"
    assert error.file == "inline_compile.ex"
    assert error.line == 6
    {target, _} = generated_identity(owner, path("invalid"))
    refute Code.ensure_loaded?(target)

    compile_source(owner, """
    action [host: :test, declaration: "valid", role: :action], :callback, nil do
      params when is_map_key(params, :first) when is_map_key(params, :second) -> {:ok, params}
      _ -> {:ok, %{fallback: true}}
    end
    """)

    target = Inline.target!(owner, path("valid"))

    for params <- [%{first: true}, %{second: true}],
        do: assert(target.run(params, %{}) == {:ok, params})

    assert target.run(%{}, %{}) == {:ok, %{fallback: true}}
  end

  @tag obligation: "jido_action.inline.I3"
  test "lookup rejects non-module owners with the public identity error" do
    for owner <- [nil, "Owner", %{}, 42] do
      error = assert_raise ArgumentError, fn -> Inline.target!(owner, path("missing")) end

      assert error.message ==
               "unknown inline Action identity in #{inspect(owner)}: #{inspect(path("missing"))}"
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a host can remove a zero-arity import and use its own helper" do
    owner = unique_owner("ZeroImport")

    compile_source(owner, """
    action_zero_import [host: :test, declaration: "zero", role: :action], params do
      {:ok, Map.put(params, :marker, helper_marker())}
    end
    defp helper_marker, do: :owner_helper
    """)

    target = Inline.target!(owner, path("zero"))
    assert target.run(%{value: 1}, %{}) == {:ok, %{value: 1, marker: :owner_helper}}
  end

  @tag obligation: ["jido_action.inline.I3", "jido_action.inline.I2"]
  test "compilation rejects function scope even while the owner is open" do
    owner = unique_owner("FunctionScope")

    error =
      assert_raise CompileError, fn ->
        compile_source(owner, """
        def invalid do
          action [host: :test, declaration: "invalid", role: :action], :bound, [],
            do: {:ok, %{}}
        end
        """)
      end

    assert error.description == "inline Action compilation requires a compiling owner module"
    {target, _} = generated_identity(owner, path("invalid"))
    refute Code.ensure_loaded?(target)
  end

  @tag obligation: "jido_action.inline.I2"
  test "generated pattern lines use positive source lines or the caller line" do
    for {metadata, expected} <- [{[], 40}, {[line: 0], 40}, {[line: 1], 1}] do
      owner = unique_owner("PatternLine")
      pattern = {:params, metadata, nil}
      tag = System.unique_integer([:positive])

      Module.create(
        owner,
        quote do
          use Jido.Action.Inline

          parsed =
            Jido.Action.Inline.parse_callback!(unquote(Macro.escape(pattern)), [do: nil], __ENV__)

          compiled =
            Jido.Action.Inline.compile!([], parsed, __ENV__, default_name: "source_line")

          send(self(), {unquote(tag), compiled.declaration_ast})
        end,
        env()
      )

      assert_received {^tag, declaration}

      {_ast, lines} =
        Macro.prewalk(declaration, [], fn
          {:def, meta, _} = ast, lines -> {ast, [meta[:line] | lines]}
          ast, lines -> {ast, lines}
        end)

      assert lines == [expected]
    end
  end

  defp path(name), do: [host: :test, declaration: name, role: :action]

  defp env, do: %{__ENV__ | file: "inline_header.ex", line: 40}

  defp quoted(source), do: Code.string_to_quoted!(source, line: 40)

  defp case_clauses(source) do
    {:case, _, [_, [do: body]]} =
      Code.string_to_quoted!("case x do\n#{source}\nend", line: 40)

    body
  end

  defp parse(:bound, header, options), do: Inline.parse_bound!(header, options, env())
  defp parse(:callback, header, options), do: Inline.parse_callback!(header, options, env())

  defp unique_owner(suffix) do
    Module.concat(__MODULE__, suffix <> Integer.to_string(System.unique_integer([:positive])))
  end

  defp generated_identity(owner, path) do
    digest =
      :crypto.hash(:sha256, :erlang.term_to_binary({owner, path})) |> Base.encode16(case: :lower)

    target = Module.concat(Jido.Action.Generated.Inline, "A" <> digest)
    {target, target}
  end

  defp diagnostic_line(%{position: {line, _}}), do: line
  defp diagnostic_line(%{position: line}), do: line

  defp compile_source(owner, body, before \\ "") do
    source = """
    defmodule #{inspect(owner)} do
      #{before}
      use Jido.Action.Inline
      import #{inspect(Host)}
      #{body}
    end
    """

    Code.compile_string(source, "inline_compile.ex")
  end
end
