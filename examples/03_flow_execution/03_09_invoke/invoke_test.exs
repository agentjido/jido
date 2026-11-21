Code.require_file("invoke.ex", __DIR__)

defmodule Jido.Examples.Execution.InvokeTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Invoke compiles to one Invoke node and selects its target at run time" do
    flow = Jido.Examples.Execution.Invoke
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])
    assert %Jido.Exec.Node.Invoke{name: "tool"} = Runic.Workflow.get_component(workflow, "tool")

    assert Jido.Exec.run(flow, %{request: "calculate"}) ==
             {:ok, %{tool: "calculate", result: 42}}

    assert Jido.Exec.run(flow, %{request: "Elixir"}) ==
             {:ok, %{tool: "search", result: "Elixir"}}
  end
end
