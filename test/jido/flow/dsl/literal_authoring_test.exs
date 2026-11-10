defmodule Jido.Flow.DSL.LiteralAuthoringTest.Extension do
  use Jido.Flow.Extension

  defmacro literal_step(name, params) do
    quote do
      step unquote(name),
        action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
        params: unquote(params)
    end
  end

  defmacro literal_block_step(name, params) do
    quote do
      step unquote(name) do
        action Jido.Test.Action.Fixtures.Actions.EchoParamsAction
        unquote({:params, [], [params]})
      end
    end
  end
end

defmodule Jido.Flow.DSL.LiteralAuthoringTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I7"

  test "module aliases keep their literal meaning across declaration forms" do
    module = unique_module("Aliases")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Jido.Flow,
        name: "literal_aliases",
        extensions: [#{inspect(__MODULE__.Extension)}]

      alias String, as: Text
      alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction, as: Echo

      flow do
        step "keyword", action: Echo, params: %{module: value(Text), nested: value([%{Text => [Text]}])}
        step "block" do
          alias Jido.Test.Action.Fixtures.Actions.EchoParamsAction, as: BlockEcho
          alias String, as: BlockText
          action BlockEcho
          params %{module: value(BlockText)}
        end
        step "inline", module <- value(Text) do
          {:ok, %{module: module}}
        end
        literal_step "extension", %{module: value(Text)}
        literal_block_step "extension_block", %{module: value(Text)}
        parallel "parallel" do
          action "explicit", Echo, params: %{module: value(Text)}
          action "inline", module <- value(Text) do
            {:ok, %{module: module}}
          end
        end
        iterate "loop" do
          state Jido.Joi.map() do
            initial %{module: value(Text)}
          end
          action Echo
          params %{module: value(Text)}
          update value(%{module: Text})
          repeat 1
        end
        output %{
          module: value(Text),
          explicit: value(Elixir.Text),
          keyword: result("keyword"),
          block: result("block"),
          inline: result("inline"),
          extension: result("extension"),
          extension_block: result("extension_block"),
          parallel: result("parallel"),
          loop: result("loop")
        }
      end
    end
    """)

    flow = module.flow()

    for name <- ["keyword", "block", "inline", "extension", "extension_block"] do
      assert flow.components[name].call.params.module == String
    end

    assert flow.components["keyword"].call.params.nested == [%{String => [String]}]
    assert flow.output.module == String
    assert flow.output.explicit == Text
    assert flow.components["loop"].state.initial == %{module: String}
    assert flow.components["loop"].call.params == %{module: String}
    assert flow.components["loop"].state.update == %{module: String}

    assert {:ok, result} = Jido.Exec.run(module)
    assert result.module == String
    assert result.explicit == Text

    for name <- [:keyword, :block, :inline, :extension, :extension_block] do
      assert result[name].module == String
    end

    assert result.parallel == [
             %{name: "explicit", value: %{module: String}},
             %{name: "inline", value: %{module: String}}
           ]

    assert result.loop.state == %{module: String}
  end

  test "literal maps reject duplicate module keys after alias expansion" do
    for entries <- ["String => 1, Elixir.String => 2", "String => 1,\nString => 2", "Text => 1, String => 2"] do
      module = unique_module("Duplicate")

      assert_raise CompileError, ~r/Flow expression|duplicate Flow map key/, fn ->
        Code.compile_string("""
        defmodule #{inspect(module)} do
          use Jido.Flow, name: "duplicate_literals"
          alias String, as: Text
          flow do
            step "echo", action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
              params: value(%{#{entries}})
            output result("echo")
          end
        end
        """)
      end
    end
  end

  defp unique_module(prefix), do: Module.concat(__MODULE__, "#{prefix}#{System.unique_integer([:positive])}")
end
