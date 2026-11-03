defmodule Jido.Flow.DSL.NeedsTest do
  use ExUnit.Case, async: false
  alias JidoActionTest.FlowCodec, as: Codec
  alias JidoActionTest.Fixtures.Actions.Add

  test "keyword and block needs preserve defaults, nil, scalar, and list order" do
    for form <- [:keyword, :block],
        {field, expected} <- [
          {:omitted, []},
          {nil, []},
          {[], []},
          {"first", ["first"]},
          {["second", "first"], ["second", "first"]}
        ] do
      owner = compile_step(form, field)
      assert owner.flow().components["work"].needs == expected
    end
  end

  test "invalid needs keep their current rejection boundary" do
    for form <- [:keyword, :block] do
      error = assert_raise CompileError, fn -> compile_step(form, ["first", "first"]) end
      assert error.description == "component needs contains a duplicate"
      assert error.file == "flow_needs.ex"
      assert error.line == 7

      for value <- [:invalid, ["first", 42]] do
        error = assert_raise Spark.Error.DslError, fn -> compile_step(form, value) end
        assert Exception.message(error) =~ "invalid list in :needs option"
      end

      # Spark currently rejects this before the lowerer with an Enumerable error.
      assert_raise FunctionClauseError, ~r/Enumerable.List.reduce\/3/, fn ->
        compile_step(form, ["first" | :tail])
      end
    end
  end

  test "all node kinds receive normalized needs from Spark" do
    owner = unique_owner()

    compile(
      owner,
      "step \"child\", action: JidoActionTest.Fixtures.NestedFlow, params: %{}, needs: \"first\"\nmap \"mapped\", action: Add, collection: [], params: %{}, needs: \"first\"\nreduce \"reduced\", action: Add, collection: [], initial: %{}, params: %{}, needs: \"first\"\nchoice \"route\" do\n  needs \"first\"\n  option \"yes\", condition: true, action: Add, params: %{}\n  otherwise action: Add, params: %{}\nend\niterate \"loop\" do\n  needs \"first\"\n  state Jido.Joi.map(), initial: %{}\n  action Add\n  params %{}\n  repeat 1\nend\ninvoke \"next\", decision: Add, expander: Add, params: %{},\n  needs: [\"first\", \"second\", \"child\", \"mapped\", \"reduced\", \"route\", \"loop\"]\n",
      "result(\"next\")"
    )

    components = owner.flow().components

    assert Enum.map(["child", "mapped", "reduced", "route", "loop", "next"], fn name ->
             components[name].needs
           end) ==
             List.duplicate(["first"], 5) ++
               [["first", "second", "child", "mapped", "reduced", "route", "loop"]]
  end

  test "direct, and Codec boundaries still reject invalid dependencies" do
    flow =
      JidoActionTest.FlowBuilder.new!(
        name: "needs",
        components: [JidoActionTest.FlowComponent.step!(name: "first", action: Add)],
        output: %{}
      )

    {:ok, document, registry} = Codec.encode(flow)

    for value <- ["first", ["first", "first"], ["first" | :tail], ~c"*"] do
      assert {:error, _} =
               JidoActionTest.FlowComponent.step(name: "work", action: Add, needs: value)

      assert {:error, _} =
               JidoActionTest.FlowBuilder.new(%{
                 output: %{},
                 components: [
                   %{kind: :step, name: "work", action: Add, params: %{}, needs: value}
                 ],
                 name: "needs"
               })
    end

    for value <- ["first", ["first", "first"], ~c"*"] do
      invalid = put_in(document, ["components", Access.at(0), "needs"], value)
      assert {:error, _} = Codec.decode(invalid, registry)
    end
  end

  test "field guards retain duplicate, unknown, and mixed-form rejections" do
    for {declaration, error_type, message} <- [
          {"step \"work\", action: Add, params: %{}, needs: [], needs: []", CompileError,
           "duplicate Flow declaration field: :needs"},
          {"step \"work\", action: Add, params: %{}, unknown: true", Spark.Error.DslError, "unknown"},
          {"step \"work\", needs: [] do\n action Add\n params %{}\nend", CompileError,
           "expected a binding in the form name <- source"},
          {"map(\"work\", needs: [], do: (action Add; collection []; params %{}))", CompileError,
           "do not mix keyword and block fields"}
        ] do
      error = assert_raise error_type, fn -> compile(unique_owner(), declaration) end
      assert Exception.message(error) =~ message
    end
  end

  test "Spark rejects repeated block properties" do
    error =
      assert_raise Spark.Error.DslError, fn ->
        compile(
          unique_owner(),
          "step \"work\" do\n  action Add\n  params %{}\n  needs \"first\"\n  needs \"second\"\nend\n"
        )
      end

    assert Exception.message(error) =~ "Multiple values for key `:needs`"
  end

  defp compile_step(form, field) do
    field =
      if field == :omitted do
        ""
      else
        inspect(field)
      end

    declaration =
      case form do
        :keyword ->
          suffix =
            if field == "" do
              ""
            else
              ", needs: " <> field
            end

          "step \"work\", action: Add, params: %{}" <> suffix

        :block ->
          field =
            if field == "" do
              ""
            else
              "needs " <> field
            end

          "step \"work\" do
 action Add
 params %{}
 #{field}
end"
      end

    owner = unique_owner()
    compile(owner, declaration)
    owner
  end

  defp compile(owner, declaration, output \\ "%{}") do
    on_exit(fn ->
      :code.purge(owner)
      :code.delete(owner)
    end)

    Code.compile_string(
      "defmodule #{inspect(owner)} do
  use Jido.Flow, name: \"needs\"
  alias JidoActionTest.Fixtures.Actions.Add
  flow do
    step \"first\", action: Add, params: %{}
    step \"second\", action: Add, params: %{}
    #{declaration}
    output #{output}
  end
end
",
      "flow_needs.ex"
    )
  end

  defp unique_owner do
    Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")
  end
end
