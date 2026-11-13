Code.require_file("state_migration.ex", __DIR__)

defmodule Jido.Examples.Runtime.StateMigrationTest do
  use Jido.Test.Case, async: true
  @moduletag :integration

  alias Jido.Examples.StateMigration
  alias Jido.Examples.StateMigration.WalletV1ToV2
  alias Jido.Persistence

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
end
