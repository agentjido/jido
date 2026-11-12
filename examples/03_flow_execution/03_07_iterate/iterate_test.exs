Code.require_file("iterate.ex", __DIR__)

defmodule Jido.Examples.Execution.IterateTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  test "one Iterate compiles to one Iterate node" do
    flow = Jido.Examples.Execution.Iterate
    assert {:ok, workflow} = Jido.Exec.compile(flow, [])

    assert %Jido.Exec.Node.Iterate{name: "counter"} =
             Runic.Workflow.get_component(workflow, "counter")

    assert {:ok, result} = Jido.Exec.run(flow, %{start: 1, target: 3})
    assert result.state == %{count: 3}
    assert result.output == %{count: 3}
    assert result.iterations == 2

    assert {:error, %Jido.Error.ExecutionError{phase: :iterate_exhaustion}} =
             Jido.Exec.run(flow, %{start: 0, target: 10})
  end
end
