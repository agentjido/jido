Code.require_file("subflow.ex", __DIR__)

defmodule Jido.Examples.Execution.SubflowTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one child Flow compiles to one Subflow node" do
    flow = Jido.Examples.Execution.Subflow
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Subflow{name: "child", child_workflow: %Runic.Workflow{}} =
             Runic.Workflow.get_component(workflow, "child")

    assert Jido.Exec.run(flow, %{value: 4}) == {:ok, %{value: 5}}
  end
end
