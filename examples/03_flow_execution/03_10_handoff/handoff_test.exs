Code.require_file("handoff.ex", __DIR__)

defmodule Jido.Examples.Execution.HandoffTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Handoff compiles to one Handoff node and returns its successor" do
    flow = Jido.Examples.Execution.Handoff
    target = Jido.Examples.Execution.Handoff.Fulfill
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Handoff{name: "next"} =
             Runic.Workflow.get_component(workflow, "next")

    assert {:handoff, %Jido.Instruction{target: ^target, params: %{order_id: 7}} = successor, []} =
             Jido.Exec.run(flow, %{order_id: 7})

    assert Jido.Exec.run(successor) == {:ok, %{order_id: 7, status: :fulfilled}}
  end
end
