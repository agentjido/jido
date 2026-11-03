defmodule Jido.Action.InlineHostTest do
  use Covenant.Case, component: "jido_action.inline", async: false

  alias JidoActionTest.Fixtures.Action.InlineHost
  alias JidoActionTest.Fixtures.Action.InlineHost.Field

  defmodule DeclarationHooks do
    defmacro __before_compile__(env) do
      Module.get_attribute(env.module, :first_inline_declarations)
    end

    defmacro second(env) do
      Module.get_attribute(env.module, :second_inline_declarations)
    end

    defmacro callback_only(env) do
      parsed =
        Jido.Action.Inline.parse_callback!(quote(do: params), [do: quote(do: {:ok, params})], env)

      compiled =
        Jido.Action.Inline.compile!(
          Macro.escape(host: __MODULE__, declaration: "late", role: :action),
          parsed,
          env,
          default_name: "late"
        )

      compiled.declaration_ast
    end
  end

  setup do
    loaded = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    on_exit(fn ->
      for {module, _} <- :code.all_loaded(),
          not MapSet.member?(loaded, module),
          String.starts_with?(Atom.to_string(module), [
            "Elixir.Jido.Action.InlineHostTest.",
            "Elixir.Jido.Action.Generated.Inline."
          ]) do
        :code.purge(module)
        :code.delete(module)
      end
    end)
  end

  @tag obligation: "jido_action.inline.I2"
  test "a downstream bound host resolves its own fields through Expr" do
    owner =
      compile_owner(:bound, """
        action "double", value <- field(:value) * 2,
          schema: Jido.Joi.object(%{value: Jido.Joi.integer()}),
          output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()}) do
          {:ok, %{value: value}}
        end
      """)

    target = owner.action_target("double")
    assert target.name() == "double"

    assert {:ok, %Jido.Instruction{kind: :action, target: ^target}} =
             Jido.Instruction.resolve(target)

    assert %{
             value: %Jido.Expr.Operation{operator: :*, operands: [%Field{key: :value}, 2]}
           } =
             owner.action_source("double")

    assert owner.action_params("double", %{value: 3}) == {:ok, %{value: 6}}
    assert InlineHost.run(owner, "double", %{value: 3}) == {:ok, %{value: 6}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "both modes expose typed metadata, defaults, context, and lexical helpers" do
    for {mode, header, input} <- [
          {:bound, "%{name: name, suffix: suffix} <- field(:value)", %{value: %{name: " Ada "}}},
          {:callback, "%{name: name, suffix: suffix}", %{name: " Ada "}}
        ] do
      owner =
        compile_owner(mode, """
        alias Jido.Joi, as: Shape
        alias String, as: Text
        @description "Build a typed greeting"
        @schema Shape.object(%{name: Shape.string(), suffix: Shape.string() |> Shape.default("!")})
        @prefix "owner:"
        action "greet", #{header}, name: "public_greeting", description: @description,
          schema: @schema, output_schema: Shape.object(%{message: Shape.string()}), context: ctx do
          send(ctx.observer, {:body, __MODULE__, %{name: name, suffix: suffix}, ctx})
          {:ok, %{message: @prefix <> ctx.prefix <> private_helper(name) <> suffix}}
        end
        @prefix "changed:"
        defp private_helper(name), do: decorate(Text.upcase(Text.trim(name)))
        def current_prefix, do: @prefix
        """)

      target = owner.action_target("greet")
      context = %{observer: self(), prefix: "Hello ", token: make_ref()}
      assert target.name() == "public_greeting"
      assert target.description() == "Build a typed greeting"
      assert owner.current_prefix() == "changed:"

      assert target.schema().fields ==
               Jido.Joi.object(%{name: Jido.Joi.string(), suffix: Jido.Joi.string() |> Jido.Joi.default("!")}).fields

      assert target.output_schema().fields == Jido.Joi.object(%{message: Jido.Joi.string()}).fields
      refute Keyword.has_key?(target.schema().fields, :ctx)
      assert {:ok, %{name: "Ada", suffix: "!"}} = target.validate_params(%{name: "Ada"})
      refute_received {:body, ^owner, _, _}

      assert InlineHost.run(owner, "greet", input, context) ==
               {:ok, %{message: "owner:Hello [ADA]!"}}

      assert_received {:body, ^owner, %{name: " Ada ", suffix: "!"}, ^context}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "Exec rejects invalid input before either body and validates normal output" do
    for {mode, header} <- [
          {:bound, "%{value: value} <- field(:value)"},
          {:callback, "%{value: value}"}
        ] do
      owner =
        compile_owner(mode, """
        action "typed", #{header}, context: ctx,
          schema: Jido.Joi.object(%{value: Jido.Joi.integer() |> Jido.Joi.default(4)}),
          output_schema: Jido.Joi.object(%{value: Jido.Joi.integer()}) do
          send(ctx.observer, {:typed_body, __MODULE__})
          {:ok, %{value: if(ctx.bad_output, do: "invalid", else: value)}}
        end
        """)

      context = %{observer: self(), bad_output: false}
      input = if mode == :bound, do: %{value: %{value: "bad"}}, else: %{value: "bad"}

      assert {:error, %Jido.Error.ValidationError{}} =
               InlineHost.run(owner, "typed", input, context)

      # Synchronous Exec completion is the barrier for the absent body marker.
      refute_received {:typed_body, ^owner}

      target = owner.action_target("typed")
      valid = %{value: 4}
      assert target.run(valid, context) == Jido.Exec.run(target, valid, context)
      assert_received {:typed_body, ^owner}
      assert_received {:typed_body, ^owner}
      assert target.run(%{value: "bad"}, context) == {:ok, %{value: "bad"}}
      assert_received {:typed_body, ^owner}
      assert_raise FunctionClauseError, fn -> target.run(%{}, context) end
      assert Jido.Exec.run(target, %{}, context) == {:ok, %{value: 4}}
      assert_received {:typed_body, ^owner}

      assert {:error, %Jido.Error.ValidationError{}} =
               Jido.Exec.run(target, valid, %{context | bad_output: true})

      assert_received {:typed_body, ^owner}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "reusing a target does not reuse bound sources or previous execution context" do
    owner =
      compile_owner(:bound, """
      action "double", value <- field(:value) * 2, context: ctx do
        {:ok, %{value: value, prefix: ctx.prefix}}
      end
      """)

    assert InlineHost.run(owner, "double", %{value: 3}, %{prefix: "host"}) ==
             {:ok, %{value: 6, prefix: "host"}}

    target = owner.action_target("double")
    assert is_atom(target)

    assert Jido.Exec.run(target, %{value: 9}, %{prefix: "reuse"}) ==
             {:ok, %{value: 9, prefix: "reuse"}}

    assert Jido.Joi.Schema.kind(target.schema()) == :map
    assert Jido.Joi.Schema.kind(target.output_schema()) == :map
  end

  @tag obligation: "jido_action.inline.I2"
  test "custom host imports remain available in bodies and private helpers" do
    owner =
      compile_owner(:bound, """
      action "imports", [] do
        {:ok, %{body: decorate("body"), helper: private_helper()}}
      end
      defp private_helper, do: decorate("helper")
      """)

    assert InlineHost.run(owner, "imports", %{}) ==
             {:ok, %{body: "[body]", helper: "[helper]"}}
  end

  @tag obligation: "jido_action.inline.I1"
  test "source validation rejects unknown references and calls before declaration creation" do
    for source <- [
          "field(:unknown)",
          "false and field(:unknown)",
          "min(1)",
          "System.unique_integer()",
          "send(self(), :source_ran)"
        ] do
      before_targets = generated_targets()

      error =
        assert_raise CompileError, fn ->
          compile_owner(:bound, """
          action "invalid", value <- #{source},
            name: (send(self(), :metadata_ran); "invalid") do
            send(self(), :body_ran)
            {:ok, %{value: value}}
          end
          """)
        end

      assert error.description =~ "invalid inline host source"
      assert error.file == "inline_host_fixture.ex"
      assert error.line == 3
      assert generated_targets() == before_targets
      refute_received :source_ran
      refute_received :metadata_ran
      refute_received :body_ran
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "missing runtime fields and invalid operands stop before the Action body" do
    owner =
      compile_owner(:bound, """
      action "double", value <- field(:value) * 2, context: ctx do
        send(ctx.observer, :body_ran)
        {:ok, %{value: value}}
      end
      """)

    assert InlineHost.run(owner, "double", %{}, %{observer: self()}) ==
             {:error, {:missing_field, :value}}

    assert {:error, %Jido.Expr.Error{operator: :*}} =
             InlineHost.run(owner, "double", %{value: "bad"}, %{observer: self()})

    refute_received :body_ran
  end

  @tag obligation: "jido_action.inline.I1"
  test "host slots select one grammar and preserve empty and map-bound sources" do
    owner =
      compile_owner(:bound, """
      action "empty", [] do
        {:ok, %{empty: true}}
      end
      action "bindings", [left <- field(:value), right <- 2] do
        {:ok, %{value: left + right}}
      end
      """)

    assert InlineHost.run(owner, "empty", %{}) == {:ok, %{empty: true}}
    assert InlineHost.run(owner, "bindings", %{value: 3}) == {:ok, %{value: 5}}

    callback =
      compile_owner(:callback, """
      action "identity", params do
        {:ok, params}
      end
      """)

    assert callback.action_source("identity") == nil
    assert InlineHost.run(callback, "identity", %{untouched: true}) == {:ok, %{untouched: true}}

    for {mode, header} <- [{:bound, "params"}, {:callback, "value <- field(:value)"}] do
      assert_raise CompileError, fn ->
        compile_owner(mode, "action \"invalid\", #{header} do\n {:ok, %{}}\n end")
      end
    end
  end

  @tag obligation: "jido_action.inline.I3"
  test "public metadata is independent of identity and declaration names evaluate once" do
    owner =
      compile_owner(:callback, """
      action (send(self(), :name_evaluated); "first"), params, name: "shared_name" do
        {:ok, Map.put(params, :selected, :first)}
      end
      action "second", params, name: "shared_name" do
        {:ok, Map.put(params, :selected, :second)}
      end
      action (send(self(), :default_name_evaluated); "default_name"), params do
        {:ok, params}
      end
      """)

    assert_received :name_evaluated
    refute_received :name_evaluated
    assert_received :default_name_evaluated
    refute_received :default_name_evaluated
    first = owner.action_target("first")
    second = owner.action_target("second")
    refute first == second
    assert first.name() == second.name()
    assert first.name() == "shared_name"
    assert owner.action_target("default_name").name() == "default_name"
    assert Jido.Exec.run(first) == {:ok, %{selected: :first}}
    assert Jido.Exec.run(second) == {:ok, %{selected: :second}}
  end

  @tag obligation: "jido_action.inline.I3"
  test "unknown lookup is inert and does not allocate atoms" do
    owner =
      compile_owner(:callback, """
      action "known", params do
        send(self(), :body_ran)
        {:ok, params}
      end
      """)

    assert_raise ArgumentError, fn -> owner.action_target("warmup_missing") end
    missing = Enum.map(1..50, &"missing_#{&1}_#{System.unique_integer([:positive])}")

    Enum.each(missing, fn name ->
      assert_raise ArgumentError, fn -> owner.action_target(name) end
    end)

    Enum.each(missing, fn name ->
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end)

    refute_received :body_ran
  end

  @tag obligation: "jido_action.inline.I2"
  test "host hooks retain early and late targets in either registration order" do
    for first_position <- [:before, :after], second_position <- [:before, :after] do
      hooks = [
        {first_position, "@before_compile #{inspect(DeclarationHooks)}"},
        {second_position, "@before_compile {#{inspect(DeclarationHooks)}, :second}"}
      ]

      before_setup = for {:before, hook} <- hooks, into: "", do: hook <> "\n"
      after_setup = for {:after, hook} <- hooks, into: "", do: hook <> "\n"

      owner =
        compile_owner(
          :callback,
          """
          #{after_setup}
          action "early", params, context: ctx do
            send(ctx.observer, {:body, __MODULE__, "early"})
            {:ok, Map.put(params, :selected, "early")}
          end
          @first_inline_declarations (quote do
            use Jido.Action.Inline
            action "late_first", params, context: ctx do
              send(ctx.observer, {:body, __MODULE__, "late_first"})
              {:ok, Map.put(params, :selected, "late_first")}
            end
            action "late_second", params, context: ctx do
              send(ctx.observer, {:body, __MODULE__, "late_second"})
              {:ok, Map.put(params, :selected, "late_second")}
            end
          end)
          @second_inline_declarations (quote do
            Jido.Action.Inline.setup!(__ENV__)
            action "late_third", params, context: ctx do
              send(ctx.observer, {:body, __MODULE__, "late_third"})
              {:ok, Map.put(params, :selected, "late_third")}
            end
          end)
          """,
          before_setup
        )

      targets =
        for name <- ["early", "late_first", "late_second", "late_third"] do
          target = Jido.Action.Inline.target!(owner, InlineHost.path(name))
          assert owner.action_target(name) == target
          assert target.name() == name

          assert {:ok, %Jido.Instruction{kind: :action, target: ^target}} =
                   Jido.Instruction.resolve(target)

          {name, target}
        end

      assert targets |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 4
      refute_received {:body, ^owner, _}

      for {name, target} <- targets do
        assert Jido.Exec.run(target, %{value: 7}, %{observer: self()}) ==
                 {:ok, %{value: 7, selected: name}}

        assert_received {:body, ^owner, ^name}
      end

      assert_raise ArgumentError, fn -> owner.action_target("missing") end
      refute_received {:body, ^owner, _}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a host hook can emit the first Action after the owner hook" do
    owner = Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(owner)} do
      use Jido.Action.Inline
      @before_compile {#{inspect(DeclarationHooks)}, :callback_only}
    end
    """)

    target =
      Jido.Action.Inline.target!(owner,
        host: DeclarationHooks,
        declaration: "late",
        role: :action
      )

    assert target.name() == "late"
    assert Jido.Exec.run(target, %{value: 7}) == {:ok, %{value: 7}}
  end

  @tag obligation: "jido_action.inline.I2"
  test "late host declarations do not permit user clauses in the lookup function" do
    for position <- [:before, :after], defaults <- [0, 1] do
      args = if defaults == 0, do: "", else: "_ \\\\ []"
      clause = "def __jido_inline_actions__(#{args}), do: :user"
      {before, after_declaration} = if position == :before, do: {clause, ""}, else: {"", clause}

      assert_raise CompileError,
                   ~r/reserved inline Action function __jido_inline_actions__\/0/,
                   fn ->
                     compile_owner(:callback, """
                     @before_compile #{inspect(DeclarationHooks)}
                     @first_inline_declarations (quote do
                       #{before}
                       action "late", params do
                         {:ok, params}
                       end
                       #{after_declaration}
                     end)
                     """)
                   end
    end
  end

  defp compile_owner(mode, declarations, before_setup \\ "") do
    owner = Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")

    Code.compile_string(
      """
      defmodule #{inspect(owner)} do
      #{before_setup}  use #{inspect(InlineHost)}, mode: #{inspect(mode)}, fields: [:value]
      #{declarations}
      end
      """,
      "inline_host_fixture.ex"
    )

    owner
  end

  defp generated_targets do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.Jido.Action.Generated.Inline."))
    |> Enum.sort()
  end
end
