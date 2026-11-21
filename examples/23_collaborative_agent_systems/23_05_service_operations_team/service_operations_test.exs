Code.require_file("service_operations.ex", __DIR__)

defmodule Jido.Examples.Collaboration.ServiceOperationsTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Collaboration.ServiceOperations

  test "intake, assignment, quality review, and human approval resume durably" do
    jido = start_durable_jido()

    request =
      Jido.Signal.new!(
        "examples.service_operations.requested",
        %{request_id: "service-1", description: "Restore database access", priority: :high},
        source: "/examples/service-operations"
      )

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, ServiceOperations, request, now: 1_000)

    unrelated =
      Jido.Signal.new!(
        "examples.service_operations.approved",
        %{request_id: "service-other", reviewer: "operator-1"},
        source: "/examples/service-operations"
      )

    assert {:error, _reason} = Durable.signal(jido, ref, wait_id, unrelated, now: 1_500)
    assert {:ok, %Status{state: :waiting}} = Durable.status(jido, ref)

    approval =
      Jido.Signal.new!(
        "examples.service_operations.approved",
        %{request_id: "service-1", reviewer: "operator-1"},
        source: "/examples/service-operations"
      )

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, approval, now: 2_000)

    assert {:ok, result} = Durable.result(jido, ref)
    assert result.status == :approved
    assert result.assigned_team == "senior-operations"
    assert result.quality == :passed
    assert result.approval_evidence.reviewer == "operator-1"
  end

  defp start_durable_jido do
    suffix = System.unique_integer([:positive])
    name = :"service_operations_#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, "Store#{suffix}")}

    start_supervised!(
      {Jido, name: name, namespace: "examples/service-operations/#{suffix}", persistence: persistence},
      id: name
    )

    name
  end
end
