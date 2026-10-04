defmodule JidoTest.Examples.Persistence.CheckpointIdentityTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.Persistence.CheckpointIdentity, as: Probe
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Persistence

  test "load rejects a checkpoint whose Agent ID differs from the requested ID" do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    requested_id = unique_id("example-checkpoint-identity")

    agent = Probe.new!(id: requested_id, state: %{count: 7})

    assert :ok =
             Persistence.save_agent(store, agent,
               namespace: "persistence-probe",
               revision: 3
             )

    assert :ok =
             PersistenceProbeStore.rewrite_record(store, requested_id, fn record ->
               put_in(record.checkpoint.id, "different-agent")
             end)

    assert {:error, {:invalid_persistence_record, :checkpoint_identity}} =
             Persistence.load_agent(store, Probe, requested_id, namespace: "persistence-probe")
  end
end
