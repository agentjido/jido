Code.require_file("compiled_program.ex", __DIR__)

defmodule Jido.Examples.Compilation.CompiledProgramTest do
  use ExUnit.Case, async: true
  @moduletag :integration

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

    assert {:ok, workflow} = Jido.Exec.compile(flow, [])
    assert map_size(workflow.components) >= 2
  end
end
