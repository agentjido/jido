Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.ReduceTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_06_reduce/reduce.ex")
    :ok
  end

  test "one Reduce compiles to one Reduce node" do
    flow = Jido.Examples.Execution.Reduce
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Reduce{name: "total"} =
             Runic.Workflow.get_component(workflow, "total")

    assert Jido.Exec.run(flow, %{values: [1, 2, 3]}) == {:ok, %{total: 6}}
    assert Jido.Exec.run(flow, %{values: []}) == {:ok, %{total: 0}}
  end
end
