Code.require_file("../support/flows/components.ex", __DIR__)
Code.require_file("../support/flows/hostile.ex", __DIR__)

defmodule JidoActionTest.Authoring.SourceBoundaryTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Expr
  alias Jido.Flow.Ref
  alias JidoActionTest.Authoring.Hostile
  alias Jido.Test.Flow.AuthoringCompiler

  test "scoped and malformed references, unknown operators, and unsafe source fail before work" do
    for {suffix, declaration, message} <- [
          {"OutOfScope", "item()", "scoped ref outside"},
          {"BadPath", "input([:payload, -1])", "unsupported Flow expression"},
          {"UnsafeCall", "send(self(), :unsafe_executed)", "unsupported Flow expression"}
        ] do
      body = """
      step "watch", action: JidoActionTest.Authoring.Hostile.Watch,
        params: %{value: #{declaration}}
      output result("watch")
      """

      {error, source} = assert_source_error(suffix, body, message)
      assert source_line(source, error.line) =~ ~r/step|params/
    end

    refute_received :unsafe_executed
    refute_received {:hostile_action, _}

    step = Jido.Test.Flow.Component.step!(name: "watch", action: Hostile.Watch)

    assert {:error, invalid_path} =
             Jido.Test.Flow.Component.step(
               name: "bad_path",
               action: Hostile.Watch,
               params: %{value: Ref.input([:payload, -1])}
             )

    assert invalid_path.message == "flow expression contains an invalid reference path"

    assert {:error, unknown_operator} =
             Jido.Test.Flow.Builder.new(
               name: "unknown_operation",
               components: [step],
               output: %Expr.Operation{operator: :unknown, operands: [Ref.result("watch")]}
             )

    assert unknown_operator.message == "invalid Flow expression"
  end

  test "cross-kind duplicate names, short and long cycles, and absent references fail in source" do
    cases = [
      {"CrossKind",
       """
       step "same", action: JidoActionTest.Authoring.Hostile.Watch, params: %{}
       map "same", collection: [], action: JidoActionTest.Authoring.Hostile.Watch, params: %{}
       output result("same")
       """, "duplicate component name"},
      {"SelfCycle",
       """
       step "self", action: JidoActionTest.Authoring.Hostile.Watch,
         params: %{}, needs: ["self"]
       output result("self")
       """, "cycle"},
      {"LongCycle",
       """
       step "a", action: JidoActionTest.Authoring.Hostile.Watch,
         params: %{}, needs: ["b"]
       step "b", action: JidoActionTest.Authoring.Hostile.Watch,
         params: %{}, needs: ["c"]
       step "c", action: JidoActionTest.Authoring.Hostile.Watch,
         params: %{}, needs: ["a"]
       output result("a")
       """, "cycle"},
      {"MissingOutputRef",
       """
       step "known", action: JidoActionTest.Authoring.Hostile.Watch, params: %{}
       output result("missing")
       """, "unknown component"},
      {"DuplicateField",
       """
       step "known", action: JidoActionTest.Authoring.Hostile.Watch,
         action: JidoActionTest.Authoring.Hostile.Watch, params: %{}
       output result("known")
       """, "duplicate Flow declaration field"}
    ]

    for {suffix, body, message} <- cases do
      {error, source} = assert_source_error(suffix, body, message)
      assert error.line > 0
      assert source_line(source, error.line) =~ ~r/step|map|output/
    end

    refute_received {:hostile_action, _}
  end

  test "output is required, cannot be nil, and must be the final source declaration" do
    step = "step \"watch\", action: JidoActionTest.Authoring.Hostile.Watch, params: %{}"
    later = "step \"later\", action: JidoActionTest.Authoring.Hostile.Watch, params: %{}"

    cases = [
      {"MissingOutput", step, "Flow output is required"},
      {"NilOutput", "#{step}\noutput nil", "Flow output is required"},
      {"OutputNotFinal", "#{step}\noutput result(\"watch\")\n#{later}", "output must be the final Flow declaration"}
    ]

    for {suffix, body, message} <- cases do
      {error, source} = assert_source_error(suffix, body, message)
      assert error.line > 0
      assert source_line(source, error.line) =~ ~r/defmodule|flow|step|output/
    end

    valid_step = Jido.Test.Flow.Component.step!(name: "watch", action: Hostile.Watch)

    assert {:error, error} =
             Jido.Test.Flow.Builder.new(
               name: "no_inferred_output",
               components: [valid_step],
               output: nil
             )

    assert error.message == "Flow output is required"
  end

  defp assert_source_error(suffix, body, message) do
    module = unique_module(suffix)

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "authoring_source_#{suffix}"
      flow do
        #{body}
      end
    end
    """

    error =
      assert_raise CompileError, ~r/#{Regex.escape(message)}/, fn ->
        AuthoringCompiler.with_compiled(source, fn _modules -> :ok end, modules: [module])
      end

    assert error.file == "authoring_fixture.ex"
    refute Code.ensure_loaded?(module)
    {error, source}
  end

  defp source_line(source, line), do: source |> String.split("\n") |> Enum.at(line - 1)

  defp unique_module(suffix) do
    Module.concat([
      JidoActionTest.Authoring.SourceDynamic,
      "#{suffix}#{System.unique_integer([:positive])}"
    ])
  end
end
