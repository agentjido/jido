Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.StepsAndReferencesTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_02_steps_and_references/steps_and_references.ex")

    :ok
  end

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
