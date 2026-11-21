Code.require_file("checkpoint_identity_probe.ex", __DIR__)
Code.require_file("persistent_agent.ex", __DIR__)

defmodule Jido.Examples.Persistence.CheckpointIdentityTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Examples.Persistence.CheckpointIdentity, as: Probe
  alias Jido.Persistence
  alias Jido.Test.Persistence.ProbeStore

  test "load rejects a checkpoint whose Agent ID differs from the requested ID" do
    store = {ProbeStore, store: start_supervised!(ProbeStore)}
    requested_id = unique_id("example-checkpoint-identity")

    agent = Probe.instantiate!(id: requested_id, state: %{count: 7})

    assert :ok =
             Persistence.save_agent(store, agent,
               namespace: "persistence-probe",
               revision: 3
             )

    assert :ok =
             ProbeStore.rewrite_record(store, requested_id, fn record ->
               put_in(record.checkpoint.agent.id, "different-agent")
             end)

    assert {:error, {:invalid_persistence_record, :checkpoint_identity}} =
             Persistence.load_agent(store, Probe, requested_id, namespace: "persistence-probe")
  end
end
