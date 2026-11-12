Code.require_file("human_approval.ex", __DIR__)

defmodule Jido.Examples.Patterns.HumanApprovalTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  test "completes one addressed approval" do
    host = Jido.Test.Exec.WaitHost

    assert {:ok, workflow} =
             host.start(
               "example-human-approval",
               Jido.Examples.Patterns.HumanApproval,
               %{request_id: "request-1"},
               %{},
               now: 0
             )

    assert {:waiting, [%{id: wait_id}]} = host.status(workflow)
    event = %{request_id: "request-1", actor: "reviewer-1"}
    input = %{id: "approval-1", wait_id: wait_id, event: "approval.approved", payload: event}
    assert {:ok, complete} = host.accept(workflow, input, %{}, now: 1)

    assert {:complete, {:ok, %{request_id: "request-1", status: :approved}, [{:submitted, "request-1"}]}} =
             host.status(complete)
  end
end
