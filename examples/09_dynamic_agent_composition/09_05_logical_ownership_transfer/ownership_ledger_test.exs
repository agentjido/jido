Code.require_file("ownership_ledger.ex", __DIR__)
Code.require_file("../support/worker.ex", __DIR__)

defmodule Jido.Examples.OwnershipLedgerTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias Jido.Agent.Ref
  alias Jido.AgentServer
  alias Jido.Examples.{OwnershipLedger, Worker}

  setup do
    suffix = System.unique_integer([:positive])
    instance = :"ownership_ledger_#{suffix}"
    namespace = "examples/ownership-ledger/#{suffix}"
    store = {Jido.Persistence.ETS, table: :"ownership_ledger_store_#{suffix}"}
    start_supervised!({Jido, name: instance, namespace: namespace, persistence: store}, id: instance)

    worker_ref = Ref.new!(namespace: namespace, id: "worker")
    assert {:ok, ^worker_ref} = Jido.create_agent(instance, worker_ref, Worker)
    assert {:ok, worker} = Jido.activate_agent(instance, worker_ref)

    assert {:ok, ledger} =
             Jido.start_agent(instance, OwnershipLedger,
               id: "ledger",
               persistence: :inherit
             )

    assert :ok = AgentServer.await_ready(worker)
    assert :ok = AgentServer.await_ready(ledger)

    %{instance: instance, worker_ref: worker_ref, worker: worker, ledger: ledger}
  end

  test "transfer changes logical ownership but not process ownership", c do
    ref_document = Ref.to_map!(c.worker_ref)

    assert {:ok, %{status: :committed}} =
             AgentServer.call(c.ledger, OwnershipLedger.adopt_signal!(%{agent_ref: ref_document, owner: "team-a"}))

    assert {:ok, %{status: :committed}} =
             AgentServer.call(
               c.ledger,
               OwnershipLedger.transfer_signal!(%{agent_ref: ref_document, from: "team-a", to: "team-b"})
             )

    key = OwnershipLedger.ownership_key(ref_document)
    assert AgentServer.snapshot(c.ledger).agent.state.owners == %{key => "team-b"}
    assert {:ok, same_worker} = Jido.resolve_agent(c.instance, c.worker_ref)
    assert same_worker == c.worker
  end

  test "a stale transfer does not change committed ownership", c do
    ref_document = Ref.to_map!(c.worker_ref)

    assert {:ok, %{status: :committed}} =
             AgentServer.call(c.ledger, OwnershipLedger.adopt_signal!(%{agent_ref: ref_document, owner: "team-a"}))

    before = AgentServer.snapshot(c.ledger)

    assert {:ok, %{status: :failed}} =
             AgentServer.call(
               c.ledger,
               OwnershipLedger.transfer_signal!(%{agent_ref: ref_document, from: "team-x", to: "team-b"})
             )

    after_failure = AgentServer.snapshot(c.ledger)
    assert after_failure.agent == before.agent
    assert after_failure.agent_revision == before.agent_revision
  end
end
