Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.ParallelTest do
  use ExUnit.Case, async: true
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_04_parallel/parallel.ex")
    :ok
  end

  test "one Parallel block compiles to one Parallel node" do
    flow = Jido.Examples.Execution.Parallel
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Parallel{name: "checks"} =
             Runic.Workflow.get_component(workflow, "checks")

    assert Jido.Exec.run(flow, %{left: 1, middle: 2, right: 3}) ==
             {:ok,
              %{
                checks: [
                  %{name: "left", value: %{value: 2}},
                  %{name: "middle", value: %{value: 4}},
                  %{name: "right", value: %{value: 6}}
                ]
              }}
  end
end
