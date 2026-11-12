Code.require_file("single_action.ex", __DIR__)

defmodule Jido.Examples.Execution.SingleActionTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Action compiles and runs as one Action node" do
    action = Jido.Examples.Execution.SingleAction.Add

    assert {:ok, workflow} = Jido.Exec.compile(action, [])
    assert %Jido.Exec.Node.Action{name: "action"} = Runic.Workflow.get_component(workflow, "action")
    assert map_size(Runic.Workflow.components(workflow)) == 3
    assert Jido.Exec.run(action, %{value: 3, amount: 2}) == {:ok, %{value: 5}}
  end
end
