defmodule JidoTest.Persistence.CheckpointIdentityTest do
  use JidoTest.Case, async: true
  @moduletag :research
  @moduletag capability: "PERSIST-01"

  alias Jido.Examples.CheckpointIdentityProbe, as: Probe
  alias Jido.Examples.PersistenceProbeStore, as: Store
  alias Jido.Persistence

  setup do
    {:ok, store: {Store, store: start_supervised!(Store)}, id: unique_id("checkpoint-identity")}
  end

  test "a valid record retains the requested Agent ID, state, and revision", c do
    agent = Probe.new!(id: c.id, state: %{count: 7})
    assert :ok = Persistence.save_agent(c.store, agent, revision: 3)
    assert {:ok, ^agent, 3} = Persistence.load_agent_with_revision(c.store, Probe, c.id)
  end

  test "a mismatched record envelope is rejected", c do
    assert :ok = Persistence.save_agent(c.store, Probe.new!(id: c.id))

    assert :ok =
             Store.rewrite_record(c.store, Probe, c.id, &%{&1 | agent_id: "different-agent"})

    assert {:error, _} = Persistence.load_agent(c.store, Probe, c.id)
  end

  test "a matching envelope cannot hide a different Agent ID in the checkpoint", c do
    assert :ok = Probe.store_mismatched_checkpoint(c.store, c.id, "different-agent")
    assert {:error, _} = Persistence.load_agent(c.store, Probe, c.id)
  end
end
