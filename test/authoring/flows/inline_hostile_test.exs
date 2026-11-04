defmodule JidoActionTest.Authoring.InlineHostileTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Exec
  alias JidoTest.AuthoringCompiler

  test "invalid bindings and duplicate inline names point to the source declaration" do
    cases = [
      {"""
       step "bad", [value <- input(:value), value <- context(:value)] do
         {:ok, %{value: value}}
       end
       output result("bad")
       """, ~r/duplicate inline Step binding/, "step \"bad\""},
      {"""
       step "same", [] do
         {:ok, %{value: 1}}
       end
       step "same", [] do
         {:ok, %{value: 2}}
       end
       output result("same")
       """, ~r/duplicate Step name/, "step \"same\""}
    ]

    for {{body, message, marker}, index} <- Enum.with_index(cases) do
      module = unique_module("BadInline#{index}")
      source = flow_source(module, body)

      error =
        assert_raise CompileError, message, fn ->
          AuthoringCompiler.with_compiled(source, fn _modules -> :ok end, modules: [module])
        end

      assert error.file == "authoring_fixture.ex"
      assert is_integer(error.line) and error.line > 0
      assert source |> String.split("\n") |> Enum.at(error.line - 1) |> String.contains?(marker)
      refute Code.ensure_loaded?(module)
    end
  end

  test "an unavailable inline helper reports the body source line" do
    module = unique_module("MissingHelper")

    source =
      flow_source(
        module,
        """
        step "bad", [] do
          missing_inline_helper()
        end
        output result("bad")
        """
      )

    assert {:error, %CompileError{} = error, diagnostics} =
             AuthoringCompiler.with_diagnostics(source, & &1, modules: [module])

    assert error.file == "authoring_fixture.ex"

    assert Enum.any?(diagnostics, fn diagnostic ->
             diagnostic.severity == :error and
               diagnostic.message =~ "undefined function missing_inline_helper/0" and
               Path.basename(diagnostic.file) == "authoring_fixture.ex" and
               source
               |> String.split("\n")
               |> Enum.at(diagnostic_line(diagnostic) - 1)
               |> String.contains?("missing_inline_helper()")
           end)

    refute Code.ensure_loaded?(module)
  end

  test "recompiled inline code changes behavior without changing stored Flow data" do
    owner = unique_module("InlineRecompiled")

    inline_module =
      AuthoringCompiler.with_compiled(
        recompiled_source(owner, 1),
        fn _modules ->
          before = owner.flow()
          assert Exec.run(before, %{value: 3}) == {:ok, %{value: 4}}

          {_modules, diagnostics} =
            Code.with_diagnostics([log: false], fn ->
              Code.compile_string(recompiled_source(owner, 2), "authoring_fixture.ex")
            end)

          assert Enum.all?(diagnostics, &(&1.severity == :warning))
          assert owner.flow() == before
          assert Exec.run(before, %{value: 3}) == {:ok, %{value: 5}}

          before.components["calc"].call.target
        end,
        modules: [owner]
      )

    refute Code.ensure_loaded?(owner)
    refute Code.ensure_loaded?(inline_module)
  end

  defp flow_source(module, body) do
    """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "authoring_dynamic"
      flow do
        #{body}
      end
    end
    """
  end

  defp recompiled_source(module, addition) do
    """
    defmodule #{module} do
      use Jido.Flow, name: "authoring_recompiled_inline"
      flow do
        step "calc", value <- input(:value) do
          {:ok, %{value: value + #{addition}}}
        end
        output result("calc")
      end
    end
    """
  end

  defp unique_module(suffix) do
    Module.concat([
      JidoActionTest.Authoring.Dynamic,
      "#{suffix}#{System.unique_integer([:positive])}"
    ])
  end

  defp diagnostic_line(%{position: {line, _column}}), do: line
  defp diagnostic_line(%{position: line}), do: line
end
