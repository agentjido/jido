defmodule Jido.Flow.DSL.InlineActionTest do
  use Covenant.Case, component: "jido_action.inline", async: false

  alias Jido.Action.Inline

  defmodule Downstream do
    use JidoActionTest.Fixtures.Action.InlineHost, mode: :callback

    action "add", nil do
      %{value: value, amount: amount} -> {:ok, %{value: value + amount}}
      %{value: value} -> {:ok, %{value: value + 1}}
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a direct inline Step uses the shared compiler and typed host path" do
    owner = unique_owner()

    compile_source(owner, """
    step "increment", value <- input(:value), inline: [context: ctx] do
      {:ok, %{value: value + ctx.increment}}
    end
    """)

    target = owner.step_action("increment")
    path = [host: Jido.Flow, step: "increment", role: :action]

    assert target == Inline.target!(owner, path)
    assert target.__jido_inline_action__() == {owner, path}
    assert {:ok, %{value: 3}} = Jido.Exec.run(owner, %{value: 1}, %{increment: 2})
    assert {:ok, %{value: 7}} = Jido.Exec.run(target, %{value: 3}, %{increment: 4})
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline settings configure Action metadata and schemas" do
    owner = unique_owner()

    compile_source(
      owner,
      """
      step "increment", value <- input(:value),
        inline: [
          name: @action_name,
          description: "Adds one",
          schema: Z.object(%{value: Z.integer()}),
          output_schema: Z.object(%{value: Z.integer()}),
          context: ctx
        ] do
        {:ok, %{value: if(ctx[:invalid_output], do: "bad", else: add_one(value))}}
      end
      """,
      "alias Zoi, as: Z\n@action_name \"configured_action\"",
      "defp add_one(value), do: value + 1"
    )

    target = owner.step_action("increment")
    assert target.name() == "configured_action"
    assert target.description() == "Adds one"
    assert {:ok, %{value: 3}} = Jido.Exec.run(owner, %{value: 2})

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             Jido.Exec.run(target, %{value: "bad"})

    assert {:error, %Jido.Action.Error.InvalidInputError{}} =
             Jido.Exec.run(target, %{value: 2}, %{invalid_output: true})
  end

  @tag obligation: "jido_action.inline.I2"
  test "invalid Step fields do not create an inline Action" do
    for field <- [:meta, :needs] do
      owner = unique_owner()

      assert_raise Spark.Error.DslError, ~r/invalid (?:value for|list in) :#{field} option/, fn ->
        compile_source(owner, """
        step "increment", value <- input(:value), #{field}: :invalid do
          {:ok, %{value: value + 1}}
        end
        """)
      end

      refute Code.ensure_loaded?(generated_target(owner, "increment"))
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "rejected Step edits preserve the loaded Action and allow a valid retry" do
    for field <- [:meta, :needs] do
      owner = unique_owner()

      compile_source(owner, """
      step "increment", value <- input(:value),
        inline: [name: "original", description: "Adds one",
          schema: Zoi.object(%{value: Zoi.integer()}),
          output_schema: Zoi.object(%{value: Zoi.integer()})] do
        {:ok, %{value: value + 1}}
      end
      """)

      target = owner.step_action("increment")
      checksum = target.module_info(:md5)
      schema = target.schema()
      output_schema = target.output_schema()
      assert {:ok, %{value: 2}} = Jido.Exec.run(owner, %{value: 1})

      changed = """
      step "increment", value <- input(:value), #{field}: :invalid,
        inline: [name: "changed", description: "Keeps a string",
          schema: Zoi.object(%{value: Zoi.string()}),
          output_schema: Zoi.object(%{value: Zoi.string()})] do
        {:ok, %{value: value}}
      end
      """

      Code.with_diagnostics(fn ->
        assert_raise Spark.Error.DslError,
                     ~r/invalid (?:value for|list in) :#{field} option/,
                     fn ->
                       compile_source(owner, changed)
                     end
      end)

      assert target.module_info(:md5) == checksum
      assert target.name() == "original"
      assert target.description() == "Adds one"
      assert target.schema() == schema
      assert target.output_schema() == output_schema
      assert {:ok, %{value: 1}} = target.validate_params(%{value: 1})

      Code.with_diagnostics(fn ->
        compile_source(owner, String.replace(changed, "#{field}: :invalid,", ""))
      end)

      assert owner.step_action("increment") == target
      refute target.module_info(:md5) == checksum
      assert target.name() == "changed"
      assert {:ok, %{value: "value"}} = Jido.Exec.run(owner, %{value: "value"})
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "a direct inline Step uses case inside its expression body" do
    owner = unique_owner()

    compile_source(owner, """
    step "increment", operand <- input(:operand),
      inline: [schema: Zoi.object(%{operand: Zoi.number()})] do
      case operand do
        0 -> {:error, :zero}
        operand -> {:ok, %{value: 10 / operand}}
      end
    end
    """)

    assert {:ok, %{value: 5.0}} = Jido.Exec.run(owner, %{operand: 2})

    assert {:error, %Jido.Action.Error.ExecutionFailureError{message: "zero"}} =
             Jido.Exec.run(owner, %{operand: 0})
  end

  @tag obligation: "jido_action.inline.I2"
  test "Flow rejects clause bodies before generating an Action" do
    for settings <- ["", ", inline: [context: ctx]"] do
      owner = unique_owner()

      error =
        assert_raise CompileError, ~r/use case inside the inline Step body/, fn ->
          compile_source(owner, """
          step "increment", value <- input(:value)#{settings} do
            %{value: 0} -> {:ok, %{value: 0}}
            %{value: value} -> {:ok, %{value: value + 1}}
          end
          """)
        end

      assert error.file == "inline_step.ex"
      assert error.line == 6
      refute Code.ensure_loaded?(generated_target(owner, "increment"))
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "Flow rejects two separate binding arguments" do
    for tail <- [
          ", do: {:ok, %{value: left + right}}",
          ", inline: [name: \"sum\"] do\n {:ok, %{value: left + right}}\nend"
        ] do
      owner = unique_owner()

      {error, _diagnostics} =
        Code.with_diagnostics(fn ->
          assert_raise CompileError, fn ->
            compile_source(
              owner,
              "step \"increment\", left <- input(:left), right <- input(:right)" <> tail
            )
          end
        end)

      assert error.file == "inline_step.ex"
      refute Code.ensure_loaded?(generated_target(owner, "increment"))
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline settings use shared option and context validation" do
    for {inline, message} <- [
          {"context: value", ~r/context variable collides/},
          {"context: _", ~r/context must be a named variable/},
          {"name: \"one\", name: \"two\"", ~r/duplicate inline Step setting/},
          {"unknown: true", ~r/unsupported inline Step setting/},
          {"schema: Zoi.integer()", ~r/schema|configuration/}
        ] do
      owner = unique_owner()

      assert_raise CompileError, message, fn ->
        compile_source(
          owner,
          "step \"increment\", value <- 1, inline: [#{inline}], do: {:ok, %{value: value}}"
        )
      end

      refute Code.ensure_loaded?(generated_target(owner, "increment"))
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "inline Step fields reject named Action fields" do
    for field <- [
          "action: JidoActionTest.Fixtures.Actions.Add",
          "params: %{value: 1}"
        ] do
      owner = unique_owner()

      assert_raise CompileError, ~r/unsupported inline Step field/, fn ->
        compile_source(
          owner,
          "step \"increment\", [], #{field}, do: {:ok, %{value: 1}}"
        )
      end
    end
  end

  @tag obligation: "jido_action.inline.I2"
  test "Flow does not expose a generic nested inline Action" do
    declarations = [
      """
      step "increment" do
        action value <- input(:value), do: {:ok, %{value: value}}
      end
      """,
      """
      map "increment" do
        collection input(:values)
        action value <- item(), do: {:ok, %{value: value}}
      end
      """,
      """
      reduce "increment" do
        collection input(:values)
        initial %{value: 0}
        action [value <- item(), total <- accumulator(:value)], do: {:ok, %{value: total + value}}
      end
      """,
      """
      choice "increment" do
        option "selected" do
          condition true
          action [], do: {:ok, %{value: 1}}
        end
        otherwise action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 0}
      end
      """,
      """
      choice "increment" do
        option "selected", condition: false, action: JidoActionTest.Fixtures.Actions.Add, params: %{value: 0}
        otherwise do
          action [], do: {:ok, %{value: 1}}
        end
      end
      """,
      """
      iterate "increment" do
        state Zoi.map(), initial: %{value: 0}
        action value <- state(:value), do: {:ok, %{value: value + 1}}
        repeat 1
      end
      """,
      """
      invoke "increment" do
        decision value <- input(:value), do: {:ok, %{value: value}}
        expander JidoActionTest.Fixtures.Actions.Add
      end
      """,
      """
      invoke "increment" do
        decision JidoActionTest.Fixtures.Actions.Add
        params %{value: input(:value)}
        expander value, do: {:ok, value}
      end
      """,
      """
      invoke "increment" do
        decision JidoActionTest.Fixtures.Actions.Add
        params %{value: input(:value)}
        expander do
          {:ok, %{value: 1}}
        end
      end
      """,
      """
      invoke "increment" do
        decision JidoActionTest.Fixtures.Actions.Add
        params %{value: input(:value)}
        expander do
          %{value: value} -> {:ok, %{value: value}}
        end
      end
      """
    ]

    for declaration <- declarations do
      owner = unique_owner()

      Code.with_diagnostics(fn ->
        try do
          compile_source(owner, declaration)
          flunk("removed Flow inline syntax compiled")
        rescue
          error in CompileError ->
            assert error.file == "inline_step.ex"

          error in Spark.Error.DslError ->
            assert Exception.message(error) =~ "invalid value for :expander option"
        end
      end)

      refute function_exported?(owner, :__jido_inline_actions__, 0)
    end
  end

  for target <- [JidoActionTest.Fixtures.Actions.Add, Downstream.action_target("add")] do
    @tag target: target
    @tag obligation: "jido_action.inline.I2"
    test "advanced components accept Action module #{inspect(target)}", %{target: target} do
      owner = unique_owner()

      compile_source(
        owner,
        """
        map "mapped" do
          collection input(:values)
          action Target
          params %{value: item()}
        end

        reduce "total" do
          collection result("mapped")
          initial %{value: 0}
          action Target
          params %{value: accumulator(:value), amount: item(:value)}
        end

        choice "increment" do
          option "selected" do
            condition input(:selected)
            action Target
            params %{value: result("total", :value)}
          end

          otherwise action: Target, params: %{value: 0}
        end

        iterate "loop" do
          state Zoi.map(), initial: result("increment")
          action Target
          params %{value: state(:value)}
          repeat 1
        end

        invoke "finish" do
          decision Target
          expander Target
          params %{value: result("loop", [:state, :value])}
        end
        """,
        "alias #{inspect(target)}, as: Target",
        "",
        "result(\"finish\")"
      )

      components = owner.flow().components

      assert Enum.map(["mapped", "total", "increment", "loop", "finish"], fn name ->
               components[name].kind
             end) == [:map, :reduce, :choice, :iterate, :invoke]

      assert {:ok, %{value: 9}} = Jido.Exec.run(owner, %{values: [1, 2], selected: true})
      assert {:ok, %{value: 4}} = Jido.Exec.run(owner, %{values: [1, 2], selected: false})
    end
  end

  defp unique_owner,
    do: Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")

  defp compile_source(
         owner,
         declarations,
         before_code \\ "",
         after_code \\ "",
         output \\ "result(\"increment\")"
       ) do
    loaded = MapSet.new(:code.all_loaded(), &elem(&1, 0))

    try do
      source = """
      defmodule #{inspect(owner)} do
        use Jido.Flow, name: "inline_step_test"
        #{before_code}
        flow do
          #{declarations}
          output #{output}
        end
        #{after_code}
      end
      """

      Code.compile_string(source, "inline_step.ex")
    after
      owned =
        for {module, _} <- :code.all_loaded(),
            not MapSet.member?(loaded, module),
            String.starts_with?(Atom.to_string(module), [
              "Elixir.Jido.Flow.DSL.InlineActionTest.",
              "Elixir.Jido.Action.Generated.Inline."
            ]),
            do: module

      on_exit(fn ->
        for module <- owned do
          :code.purge(module)
          :code.delete(module)
        end
      end)
    end
  end

  defp generated_target(owner, name) do
    digest =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({owner, [host: Jido.Flow, step: name, role: :action]})
      )
      |> Base.encode16(case: :lower)

    Module.concat(Jido.Action.Generated.Inline, "A" <> digest)
  end
end
