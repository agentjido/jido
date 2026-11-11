Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.CompileToRunicTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_13_compile_to_runic/compile_to_runic.ex")

    :ok
  end

  test "compile exposes the Runic workflow and direct execution projects a Jido result" do
    example = Jido.Examples.Execution.CompileToRunic
    assert {:ok, %Runic.Workflow{} = workflow} = apply(example, :compile, [])

    assert %Jido.Exec.Node.Action{name: "add"} = Runic.Workflow.get_component(workflow, "add")

    assert %Jido.Exec.Node.Action{name: "multiply"} =
             Runic.Workflow.get_component(workflow, "multiply")

    connections = apply(example, :connection_summary, [workflow])
    assert {"add", "multiply"} in connections
    assert apply(example, :execute, [workflow, %{value: 4}]) == {:ok, %{value: 18}}
  end
end
