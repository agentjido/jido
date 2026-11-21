Code.require_file("choice.ex", __DIR__)

defmodule Jido.Examples.Execution.ChoiceTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Choice compiles to one Choice node" do
    flow = Jido.Examples.Execution.Choice
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])
    assert %Jido.Exec.Node.Choice{name: "grade"} = Runic.Workflow.get_component(workflow, "grade")

    assert Jido.Exec.run(flow, %{score: 95}) == {:ok, %{label: "excellent"}}
    assert Jido.Exec.run(flow, %{score: 70}) == {:ok, %{label: "passing"}}
    assert Jido.Exec.run(flow, %{score: 40}) == {:ok, %{label: "needs_work"}}
  end
end
