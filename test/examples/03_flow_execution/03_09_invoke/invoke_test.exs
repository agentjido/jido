Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.InvokeTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_09_invoke/invoke.ex")
    :ok
  end

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
