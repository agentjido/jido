Code.require_file("../../../support/loader.exs", __DIR__)

defmodule JidoTest.Examples.Execution.WaitAndSignalTest do
  use ExUnit.Case, async: false
  @moduletag :example
  setup_all do
    JidoTest.Examples.Loader.require_source!("flow/02_execution/02_12_wait_and_signal/wait_and_signal.ex")
    :ok
  end

  test "deterministic signals reject a miss and complete on one match" do
    host = Jido.Exec.Test.WaitHost

    assert {:ok, workflow} =
             host.start(
               "example-wait",
               Jido.Examples.Execution.WaitAndSignal,
               %{request_id: "r1"},
               %{},
               now: 0
             )

    assert {:waiting, [%{id: wait_id, options: options}]} = host.status(workflow)
    assert Enum.map(options, & &1.name) == ["approved", "denied", "expired"]

    miss = %{id: "miss", wait_id: wait_id, event: "example.approved", payload: %{request_id: "other"}}

    assert {:error, %Jido.Error.ValidationError{details: %{reason: :unmatched_input}}} =
             host.accept(workflow, miss, %{}, now: 1)

    event = %{request_id: "r1", actor: "user"}
    input = %{id: "match", wait_id: wait_id, event: "example.approved", payload: event}
    assert {:ok, complete} = host.accept(workflow, input, %{}, now: 1)
    assert {:complete, {:ok, result}} = host.status(complete)
    assert result.selected == "approved"
    assert result.value == event
  end
end
