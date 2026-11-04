Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Compilation.DependencyGraphTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("02_flow_authoring/02_02_dependency_graph/dependency_graph.ex")

    :ok
  end

  test "derives exact data and control dependencies" do
    flow = apply(Jido.Examples.Compilation.DependencyGraph, :flow, [])

    assert Jido.Flow.dependencies(flow) ==
             {:ok,
              %{
                "audit" => %{needs: [], references: [], effective: []},
                "charge" => %{needs: [], references: ["load"], effective: ["load"]},
                "load" => %{needs: [], references: [], effective: []},
                "save" => %{
                  needs: ["audit"],
                  references: ["charge"],
                  effective: ["audit", "charge"]
                }
              }}
  end

  test "rejects a control dependency cycle" do
    definition = apply(Jido.Examples.Compilation.DependencyGraph, :definition, [])

    components =
      definition.components
      |> Enum.map(fn
        %{name: "audit"} = component -> Map.put(component, :needs, ["save"])
        component -> component
      end)

    assert {:error, error} =
             definition
             |> Map.put(:components, components)
             |> Jido.Flow.new()

    assert error.message == "flow dependency graph contains a cycle"
    assert Enum.sort(error.details.components) == ["audit", "save"]
  end
end
