Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.SingleActionTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_01_single_action/single_action.ex")
    :ok
  end

  test "one Action compiles and runs as one Action node" do
    action = Jido.Examples.Execution.SingleAction.Add

    assert {:ok, workflow} = Jido.Exec.compile(action, [])
    assert %Jido.Exec.Node.Action{name: "action"} = Runic.Workflow.get_component(workflow, "action")
    assert map_size(Runic.Workflow.components(workflow)) == 3
    assert Jido.Exec.run(action, %{value: 3, amount: 2}) == {:ok, %{value: 5}}
  end
end
