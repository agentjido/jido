Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Patterns.HumanApprovalTest do
  use ExUnit.Case, async: false
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/04_patterns/04_01_human_approval/human_approval.ex")

    :ok
  end

  test "completes one addressed approval" do
    host = Jido.Exec.Test.WaitHost

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
