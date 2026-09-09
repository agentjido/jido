defmodule JidoTest.Examples.CheckpointIdentityTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.Examples.CheckpointIdentityProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore
  alias Jido.Persistence

  test "load rejects a checkpoint whose Agent ID differs from the requested ID" do
    store = {PersistenceProbeStore, store: start_supervised!(PersistenceProbeStore)}
    requested_id = unique_id("example-checkpoint-identity")

    assert :ok = Probe.store_mismatched_checkpoint(store, requested_id, "different-agent")

    assert {:error, {:invalid_persistence_record, :checkpoint_identity}} =
             Persistence.load_agent(store, Probe, requested_id)
  end
end
