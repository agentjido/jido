defmodule JidoTest.Examples.Runtime.StateMigrationTest do
  use JidoTest.Case, async: true

  @moduletag :example

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.StateMigration
  alias Jido.Examples.StateMigration.WalletV1ToV2
  alias Jido.Persistence

  test "one upgrade commits the definition and state while preserving identity", c do
    server = start_wallet(c)
    before = Server.snapshot(server)

    assert {:ok, upgraded, []} = Server.upgrade(server, WalletV1ToV2)
    assert upgraded.vsn == 2
    assert upgraded.state == %{wallet: %{format: 2, amount: 100, currency: "USD"}}
    assert upgraded.schema != before.agent.schema
    assert upgraded.id == before.agent.id
    assert upgraded.module == StateMigration
    assert %{agent: ^upgraded, state_version: 1} = Server.snapshot(server)
    assert Jido.whereis_agent(c.jido, upgraded.id) == server
    assert {:ok, _} = Zoi.parse(upgraded.schema, upgraded.state)
    assert {:error, _} = Zoi.parse(upgraded.schema, before.agent.state)
  end

  test "invalid target data preserves the definition, state, and revision", c do
    server = start_wallet(c)
    before = Server.snapshot(server)

    assert {:error, _} = Server.upgrade(server, WalletV1ToV2, context: %{currency: "INVALID"})
    assert Server.snapshot(server) == before
    assert {:ok, upgraded, []} = Server.upgrade(server, WalletV1ToV2)
    assert upgraded.vsn == 2
  end

  test "a saved upgrade restores its definition and state without the source definition" do
    original = StateMigration.instantiate!(id: "saved-wallet")
    assert {:ok, saved} = Persistence.snapshot(original)
    assert {:ok, upgraded} = Persistence.upgrade(saved, WalletV1ToV2)
    assert {:ok, saved_upgrade} = Persistence.snapshot(upgraded)
    assert {:ok, restored} = Persistence.restore(saved_upgrade)
    assert restored == upgraded
    assert restored.module == StateMigration
    assert restored.vsn == 2
    assert StateMigration.instantiate!(id: "saved-wallet").vsn == 1
    assert restored.state == %{wallet: %{format: 2, amount: 100, currency: "USD"}}
  end

  test "the Action accepts an upgraded snapshot and rejects an unsupported version" do
    assert {:ok, saved} = Persistence.snapshot(StateMigration.instantiate!(id: "saved-wallet"))
    assert {:ok, upgraded} = Persistence.upgrade(saved, WalletV1ToV2)
    assert {:ok, saved_upgrade} = Persistence.snapshot(upgraded)
    assert {:ok, ^upgraded} = Persistence.upgrade(saved_upgrade, WalletV1ToV2)
    assert {:error, _} = Persistence.upgrade(put_in(saved.agent.vsn, 3), WalletV1ToV2)
  end

  defp start_wallet(c) do
    {:ok, server} =
      JidoTest.ExampleRuntime.start_agent(c.jido, StateMigration, id: unique_id("wallet"))

    assert :ok = Server.await_ready(server)
    server
  end
end
