Code.require_file("map.ex", __DIR__)

defmodule Jido.Examples.Execution.MapTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Map compiles to one Map node and keeps item order" do
    flow = Jido.Examples.Execution.Map
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])
    assert %Jido.Exec.Node.Map{name: "items"} = Runic.Workflow.get_component(workflow, "items")

    assert {:ok, %{items: [first, failed, third]}} =
             Jido.Exec.run(flow, %{values: [2, -1, 4]})

    assert first == %{status: :ok, value: %{index: 0, value: 4}}
    assert failed.status == :error
    assert third == %{status: :ok, value: %{index: 2, value: 8}}
  end
end
