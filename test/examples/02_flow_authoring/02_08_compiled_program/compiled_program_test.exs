Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Compilation.CompiledProgramTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("02_flow_authoring/02_08_compiled_program/compiled_program.ex")

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
