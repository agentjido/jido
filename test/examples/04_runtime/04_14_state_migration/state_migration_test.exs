defmodule JidoTest.Examples.Runtime.StateMigrationTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.StateMigration
  alias Jido.Examples.StateMigration.StrictWallet
  alias JidoTest.Persistence.ProbeStore

  test "a compatible schema migrates domain and Plugin state in one commit", c do
    {:ok, server} = Jido.start_agent(c.jido, StateMigration, id: unique_id("wallet"))
    assert Server.snapshot(server).state_version == 0
    assert {:ok, agent} = StateMigration.migrate(server)
    assert agent.state == migrated_state()
    assert Server.snapshot(server).state_version == 1
    assert Jido.whereis_agent(c.jido, agent.id) == server

    assert {:ok, repeated} = StateMigration.migrate(server)
    assert repeated.state == agent.state
    assert {:error, _reason} = StateMigration.migrate(server, "another-upgrade")
    assert Server.agent(server) == repeated
  end

  test "invalid target state leaves domain and Plugin state unchanged", c do
    {:ok, server} = Jido.start_agent(c.jido, StateMigration)
    before = Server.snapshot(server)
    assert {:error, _reason} = StateMigration.migrate(server, "bad-currency", "INVALID")
    assert Server.snapshot(server) == before
    assert {:ok, agent} = StateMigration.migrate(server)
    assert agent.state == migrated_state()
  end

  test "a saved migration restores and remains idempotent", c do
    persistence = persistence()
    id = unique_id("saved-wallet")

    {:ok, server} =
      Jido.start_agent(c.jido, StateMigration, id: id, persistence: persistence)

    assert {:ok, _agent} = StateMigration.migrate(server)
    assert :ok = Jido.hibernate(c.jido, server)

    assert {:ok, replacement} =
             Jido.thaw(c.jido, StateMigration, id, persistence: persistence)

    assert replacement != server
    assert Server.agent(replacement).state == migrated_state()
    assert Server.snapshot(replacement).state_version == 1
    assert {:ok, repeated} = StateMigration.migrate(replacement)
    assert repeated.state == migrated_state()
  end

  test "a strict definition upgrade persists the new definition and complete state", c do
    persistence = persistence()
    id = unique_id("strict-wallet")

    {:ok, server} =
      Jido.start_agent(c.jido, StrictWallet, id: id, persistence: persistence)

    assert {:ok, upgraded} = StateMigration.upgrade(server)
    assert upgraded.state == migrated_state()
    assert upgraded.module == StateMigration.MigratedWallet
    assert Jido.whereis_agent(c.jido, upgraded.id) == server
    assert Server.snapshot(server).state_version == 1

    assert :ok = Jido.hibernate(c.jido, server)

    assert {:ok, restored} =
             Jido.thaw(c.jido, StateMigration.MigratedWallet, id, persistence: persistence)

    assert Server.agent(restored).state == migrated_state()
    assert Server.snapshot(restored).state_version == 1
  end

  defp persistence do
    store = start_supervised!(ProbeStore)
    {ProbeStore, store: store}
  end

  defp migrated_state do
    %{
      wallet: %{format: 2, amount: 100, currency: "USD"},
      audit: %{format: 2, entries: ["opened"], upgrade_id: "wallet-1-to-2"}
    }
  end
end
