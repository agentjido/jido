defmodule JidoTest.Examples.StateMigrationTest do
  use JidoTest.Case, async: true
  @moduletag :example
  alias Jido.Examples.{PersistenceProbeStore, StateMigration}
  alias StateMigration.{CompatibleWallet, StrictWallet}
  alias Jido.AgentServer, as: Server

  test "a predeclared schema migrates domain and Plugin state in one live commit", c do
    {:ok, server} = Jido.start_agent(c.jido, CompatibleWallet, id: unique_id("wallet"))
    assert Server.snapshot(server).state_version == 0
    assert {:ok, agent} = StateMigration.migrate(server)
    assert agent.state == migrated_state()
    assert Server.snapshot(server).state_version == 1
    assert Jido.whereis_agent(c.jido, agent.id) == server

    assert {:ok, repeated} = StateMigration.migrate(server)
    assert repeated.state == agent.state
    assert {:error, _} = StateMigration.migrate(server, "another-upgrade")
    assert Server.agent(server) == repeated
  end

  test "invalid target state leaves both domain and Plugin state unchanged", c do
    {:ok, server} = Jido.start_agent(c.jido, CompatibleWallet)
    before = Server.snapshot(server)
    assert {:error, _} = StateMigration.migrate(server, "bad-currency", "INVALID")
    assert Server.snapshot(server) == before
    assert {:ok, agent} = StateMigration.migrate(server)
    assert agent.state == migrated_state()
  end

  test "a saved migration survives process replacement and does not run twice", c do
    store = start_supervised!(PersistenceProbeStore)
    persistence = {PersistenceProbeStore, store: store}
    id = unique_id("saved-wallet")

    {:ok, server} =
      Jido.start_agent(c.jido, CompatibleWallet, id: id, persistence: persistence)

    assert {:ok, _} = StateMigration.migrate(server)
    assert :ok = Jido.hibernate(c.jido, server)

    assert {:ok, replacement} =
             Jido.thaw(c.jido, CompatibleWallet, id, persistence: persistence)

    assert replacement != server
    assert Server.agent(replacement).state == migrated_state()
    assert Server.snapshot(replacement).state_version == 1
    assert {:ok, repeated} = StateMigration.migrate(replacement)
    assert repeated.state == migrated_state()
  end

  test "a running old definition can migrate to a state format outside its old schema", c do
    {:ok, server} = Jido.start_agent(c.jido, StrictWallet, id: unique_id("strict-wallet"))

    assert {:ok, upgraded} = StateMigration.migrate(server)
    assert upgraded.state == migrated_state()
    assert Jido.whereis_agent(c.jido, upgraded.id) == server
    assert Server.snapshot(server).state_version == 1
  end

  defp migrated_state do
    %{
      wallet: %{format: 2, amount: 100, currency: "USD"},
      audit: %{format: 2, entries: ["opened"], upgrade_id: "wallet-1-to-2"}
    }
  end
end
