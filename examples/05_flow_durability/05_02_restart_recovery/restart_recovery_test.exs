Code.require_file("restart_recovery.ex", __DIR__)

defmodule Jido.Examples.Durability.RestartRecoveryTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  alias Jido.Durable
  alias Jido.Durable.Status
  alias Jido.Examples.Durability.RestartRecovery

  test "a waiting Flow resumes after its Jido instance restarts" do
    suffix = System.unique_integer([:positive])
    jido = :"restart_recovery_#{suffix}"
    child_id = {:restart_recovery_jido, suffix}
    namespace = "examples/restart-recovery/#{suffix}"
    persistence = {Jido.Persistence.ETS, table: Module.concat(__MODULE__, Store)}
    child = {Jido, name: jido, namespace: namespace, persistence: persistence}

    start_supervised!(child, id: child_id)

    {:ok, request} =
      Jido.Signal.new("examples.durable.order", %{order_id: "order-42"}, source: "/examples/durable")

    assert {:ok, %Status{state: :waiting, waits: [%{id: wait_id}], ref: ref}} =
             Durable.start(jido, RestartRecovery, request, now: 1_000)

    assert :ok = stop_supervised(child_id)
    start_supervised!(child, id: child_id)

    assert {:ok, %Status{state: :waiting, waits: [%{id: ^wait_id}]}} =
             Durable.status(jido, ref)

    {:ok, approval} =
      Jido.Signal.new(
        "examples.durable.order.approved",
        %{order_id: "order-42", approved: true},
        source: "/examples/approvals"
      )

    assert {:ok, %Status{state: :completed}} =
             Durable.signal(jido, ref, wait_id, approval, now: 2_000)

    assert {:ok, %{order_id: "order-42", approved: true}} = Durable.result(jido, ref)
  end
end
