Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.ChildFlowTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_11_child_flow/child_flow.ex")
    :ok
  end

  test "executes the child flow as a compiled component" do
    module = Jido.Examples.Execution.ChildFlow

    assert Jido.Exec.run(module, %{value: 4}) == {:ok, %{value: 5}, [:child_effect]}

    assert %Runic.Workflow{} =
             module
             |> Jido.Exec.compile!()
             |> Runic.Workflow.get_component("child")
  end
end
