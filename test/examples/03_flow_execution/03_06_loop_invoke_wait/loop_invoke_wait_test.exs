Code.require_file("../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.LoopInvokeWaitTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("03_flow_execution/03_06_loop_invoke_wait/loop_invoke_wait.ex")
    :ok
  end

  test "a child wait resumes from one matching event" do
    host = Jido.Exec.Test.WaitHost

    assert {:ok, workflow} =
             host.start(
               "example-loop-wait",
               Jido.Examples.Execution.LoopInvokeWait,
               %{request_id: "r1"},
               %{},
               now: 0
             )

    assert {:waiting, [%{id: wait_id, event: "request.approved"}]} = host.status(workflow)
    event = %{request_id: "r1", actor: "user"}
    input = %{id: "approval", wait_id: wait_id, event: "request.approved", payload: event}
    assert {:ok, complete} = host.accept(workflow, input, %{}, now: 1)

    assert {:complete, {:ok, output, [{:attempt, 0}, {:attempt, 1}]}} = host.status(complete)
    assert output.attempts.iterations == 2
    assert output.approval == event
  end
end
