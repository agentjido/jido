Code.require_file("../../support/loader.exs", __DIR__)

alias JidoTest.Examples.Loader
Loader.require_source!("13_persistence/13_01_persistent_agent/checkpoint_identity_probe.ex")
Loader.require_source!("13_persistence/13_01_persistent_agent/persistent_agent.ex")

defmodule JidoTest.Examples.Persistence.CheckpointIdentityTest do
  use JidoTest.Case, async: true
  @moduletag :example

  setup_all do
    JidoTest.Examples.Loader.require_source!("13_persistence/13_01_persistent_agent/checkpoint_identity_probe.ex")

    :ok
  end

  alias Jido.Examples.Persistence.CheckpointIdentity, as: Probe
  alias Jido.Persistence
  alias JidoTest.Persistence.ProbeStore

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
