defmodule Jido.Flow.DSL.OutputSourceTest.Extension do
  use Jido.Flow.Extension

  defmacro finish(value) do
    quote do
      output unquote(value)
    end
  end
end

defmodule Jido.Flow.DSL.OutputSourceTest do
  use ExUnit.Case, async: false

  test "Output errors keep their declaration location with and without debug info" do
    previous = Code.compiler_options()

    try do
      for debug_info <- [true, false],
          declaration <- ["output", "finish"],
          {value, following} <- [
            {"Date.utc_today()", ""},
            {"result(\"missing\")", ""},
            {"%{}", "step \"late\", action: JidoActionTest.Fixtures.Actions.EchoParamsAction, params: %{}"}
          ] do
        Code.compiler_options(debug_info: debug_info)
        module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")
        file = "output_source_#{debug_info}_#{declaration}.ex"

        source = """
        defmodule #{inspect(module)} do
          use Jido.Flow, name: "output_source", extensions: [#{inspect(__MODULE__.Extension)}]
          flow do
            step "first", action: JidoActionTest.Fixtures.Actions.EchoParamsAction, params: %{}
            #{declaration}(#{value})
            #{following}
          end
        end
        """

        error = assert_raise CompileError, fn -> Code.compile_string(source, file) end
        assert error.file == file
        assert error.line == 5, inspect({debug_info, declaration, value, error})
      end
    after
      Code.compiler_options(previous)
    end
  end

  test "Output source maps stay separate from canonical and stored Flow data" do
    module = Module.concat(__MODULE__, "Valid#{System.unique_integer([:positive])}")

    Code.compile_string(
      """
      defmodule #{inspect(module)} do
        use Jido.Flow, name: "output_source"
        flow do
          step "first", action: JidoActionTest.Fixtures.Actions.EchoParamsAction, params: %{}
          output %{}
        end
      end
      """,
      "valid_output_source.ex"
    )

    assert module.__jido_flow_source_map__()[[:output]] ==
             %{file: "valid_output_source.ex", line: 5}

    expected =
      JidoActionTest.FlowBuilder.new!(
        name: "output_source",
        components: [
          JidoActionTest.FlowComponent.step!(
            name: "first",
            action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
            params: %{}
          )
        ],
        output: %{}
      )

    assert module.flow() == expected
    assert {:ok, document, registry} = JidoActionTest.GeneratedFlowCodec.encode(module.flow())
    assert {:ok, ^expected} = JidoActionTest.FlowCodec.decode(document, registry)
  end

  test "a Flow with only output reports the shared component validation error" do
    module = Module.concat(__MODULE__, "Empty#{System.unique_integer([:positive])}")

    error =
      assert_raise CompileError, fn ->
        Code.compile_string(
          """
          defmodule #{inspect(module)} do
            use Jido.Flow, name: "empty_source"
            flow do
              output %{}
            end
          end
          """,
          "empty_source.ex"
        )
      end

    assert error.description == "Flow must declare at least one component"
    assert error.file == "empty_source.ex"
  end
end
