Code.require_file("steps_and_references.ex", __DIR__)

defmodule Jido.Examples.Execution.StepsAndReferencesTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "references connect three Action nodes" do
    flow = Jido.Examples.Execution.StepsAndReferences
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    for name <- ["add_one", "double", "label"] do
      assert %Jido.Exec.Node.Action{name: ^name} = Runic.Workflow.get_component(workflow, name)
    end

    assert Jido.Exec.run(flow, %{value: 3}, %{prefix: "total"}) ==
             {:ok, %{value: 8, label: "total=8"}}
  end
end
