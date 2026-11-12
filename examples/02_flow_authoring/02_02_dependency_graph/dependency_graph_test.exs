Code.require_file("dependency_graph.ex", __DIR__)

defmodule Jido.Examples.Compilation.DependencyGraphTest do
  use ExUnit.Case, async: true
  @moduletag :integration

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
