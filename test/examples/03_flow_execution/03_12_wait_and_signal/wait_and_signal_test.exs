Code.require_file("../../support/loader.exs", __DIR__)

defmodule Jido.Examples.Execution.WaitAndSignalTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    Jido.Test.Examples.Loader.require_source!("03_flow_execution/03_12_wait_and_signal/wait_and_signal.ex")

    :ok
  end

  test "one Selection compiles to one Wait node and resumes through a host" do
    flow = Jido.Examples.Execution.WaitAndSignal
    host = Jido.Test.Exec.WaitHost

    assert {:ok, compiled} = Jido.Exec.compile(flow, [])
    assert %Jido.Exec.Node.Wait{name: "decision"} = Runic.Workflow.get_component(compiled, "decision")

    assert {:error, %Jido.Error.ValidationError{details: %{reason: :unsupported_host}}} =
             Jido.Exec.run(flow, %{request_id: "r1"})

    assert {:ok, workflow} = host.start("example-wait", flow, %{request_id: "r1"}, %{}, now: 0)
    assert {:waiting, [%{id: wait_id}]} = host.status(workflow)

    input = %{
      id: "signal-1",
      wait_id: wait_id,
      event: "example.approved",
      payload: %{request_id: "r1", actor: "user"}
    }

    assert {:ok, complete} = host.accept(workflow, input, %{}, now: 1)
    assert {:complete, {:ok, result}} = host.status(complete)
    assert result.selected == "approved"
    assert result.value == input.payload
  end
end
