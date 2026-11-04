Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.CompiledProgramTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/01_compilation/01_09_compiled_program/compiled_program.ex")

    :ok
  end

  test "keeps Map and Choice as two shallow named components" do
    flow = apply(Jido.Examples.Compilation.CompiledProgram, :flow, [])
    assert Map.keys(flow.components) == ["items", "selected"]

    assert Jido.Flow.dependencies(flow) ==
             {:ok,
              %{
                "items" => %{needs: [], references: [], effective: []},
                "selected" => %{
                  needs: [],
                  references: ["items"],
                  effective: ["items"]
                }
              }}

    assert map_size(Jido.Exec.compile!(flow).components) >= 2
  end
end
