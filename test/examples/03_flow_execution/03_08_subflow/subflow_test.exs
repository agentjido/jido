Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.SubflowTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_08_subflow/subflow.ex")
    :ok
  end

  test "one child Flow compiles to one Subflow node" do
    flow = Jido.Examples.Execution.Subflow
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Subflow{name: "child", child_workflow: %Runic.Workflow{}} =
             Runic.Workflow.get_component(workflow, "child")

    assert Jido.Exec.run(flow, %{value: 4}) == {:ok, %{value: 5}}
  end
end
