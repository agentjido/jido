Code.require_file("../support/jido_flow/components.ex", __DIR__)
Code.require_file("../support/jido_flow/hostile.ex", __DIR__)
Code.require_file("../support/jido_flow/extension.ex", __DIR__)

defmodule Jido.Flow.Authoring.ExtensionTest do
  use ExUnit.Case, async: false
  @moduletag :authoring

  alias Jido.Test.Flow.Authoring.Extension
  alias Jido.Test.Flow.AuthoringCompiler

  test "a host extension expands to ordinary canonical source declarations" do
    assert Extension.Extended.flow() == Extension.Plain.flow()

    assert Jido.Exec.run(Extension.Extended, %{value: 7}, %{observer: self()}) ==
             {:ok, %{id: "observed", value: 7}}

    assert_receive {:hostile_action, %{id: "observed", value: 7}}
  end

  test "an extension error points to the source call" do
    module = unique_module("InvalidExtension")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow,
        name: "authoring_invalid_extension",
        extensions: [Jido.Test.Flow.Authoring.Extension.WatchStep]

      flow do
        watch_step("observed", result("missing"))
        output result("observed")
      end
    end
    """

    error =
      assert_raise CompileError, fn ->
        AuthoringCompiler.with_compiled(source, fn _modules -> :ok end, modules: [module])
      end

    assert error.file == "authoring_fixture.ex"
    assert error.line == 7
    assert error.description =~ "unknown component"
    refute Code.ensure_loaded?(module)
  end

  defp unique_module(suffix) do
    Module.concat([
      Jido.Test.Flow.Authoring.Extension.Dynamic,
      "#{suffix}#{System.unique_integer([:positive])}"
    ])
  end
end
