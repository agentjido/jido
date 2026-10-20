defmodule JidoTest.Persistence.CheckpointIdentityTest do
  use JidoTest.Case, async: true
  use Covenant.Case, component: "jido.persistence", async: true

  alias Jido.Persistence
  alias JidoTest.Persistence.CheckpointIdentityProbe, as: Probe
  alias JidoTest.Persistence.ProbeStore, as: Store

  setup do
    {:ok, store: {Store, store: start_supervised!(Store)}, id: unique_id("checkpoint-identity")}
  end

  @tag obligation: ["jido.persistence.I2", "jido.persistence.I12"]
  test "a valid record retains the requested Agent ID, state, and revision", c do
    agent = Probe.instantiate!(id: c.id, state: %{count: 7})

    assert :ok =
             Persistence.save_agent(c.store, agent, namespace: "persistence-probe", revision: 3)

    assert {:ok, ^agent, 3} =
             Persistence.load_agent_with_revision(c.store, Probe, c.id,
               namespace: "persistence-probe"
             )
  end

  @tag obligation: ["jido.persistence.I2", "jido.persistence.I5"]
  test "a mismatched record envelope is rejected", c do
    assert :ok =
             Persistence.save_agent(c.store, Probe.instantiate!(id: c.id),
               namespace: "persistence-probe"
             )

    assert :ok =
             Store.rewrite_record(c.store, c.id, &%{&1 | agent_id: "different-agent"})

    assert {:error, _} =
             Persistence.load_agent(c.store, Probe, c.id, namespace: "persistence-probe")
  end

  @tag obligation: ["jido.persistence.I2", "jido.persistence.I6", "jido.persistence.I11"]
  test "a matching envelope cannot hide a different Agent ID in the checkpoint", c do
    assert :ok =
             Persistence.save_agent(c.store, Probe.instantiate!(id: c.id, state: %{count: 7}),
               namespace: "persistence-probe",
               revision: 3
             )

    assert :ok =
             Store.rewrite_record(c.store, c.id, fn record ->
               put_in(record.checkpoint.agent.id, "different-agent")
             end)

    assert {:error, _} =
             Persistence.load_agent(c.store, Probe, c.id, namespace: "persistence-probe")
  end
end
