defmodule JidoTest.Agent.Identity.MigrationTest do
  use ExUnit.Case, async: false

  alias Jido.Agent.Identity
  alias Jido.Persist
  alias Jido.Storage.ETS

  defmodule MigrationAgent do
    @moduledoc false
    use Jido.Agent, name: "identity_migration_agent"
  end

  defp legacy_identity(fields \\ %{}) do
    Map.merge(
      %{
        __struct__: Jido.Identity,
        rev: 2,
        profile: %{age: 5, origin: :legacy},
        created_at: 1_000,
        updated_at: 2_000
      },
      fields
    )
  end

  defp unique_table, do: :"identity_migration_#{System.unique_integer([:positive])}"

  describe "migrate_legacy/1" do
    test "converts legacy Jido.Identity agent identity structs" do
      assert %Identity{} = migrated = Identity.migrate_legacy(legacy_identity())
      assert migrated.rev == 2
      assert migrated.profile == %{age: 5, origin: :legacy}
      assert migrated.created_at == 1_000
      assert migrated.updated_at == 2_000
    end

    test "leaves custom state under the same key unchanged" do
      custom = %{__struct__: Jido.Identity, principal_id: "agent_123"}

      assert Identity.migrate_legacy(custom) == custom
    end

    test "leaves Jido.Identity-shaped values with extra fields unchanged" do
      custom = legacy_identity(%{principal_id: "agent_123"})

      assert Identity.migrate_legacy(custom) == custom
    end
  end

  describe "Persist.thaw/3" do
    test "migrates legacy checkpoint identity state before restore" do
      table = unique_table()
      storage = {ETS, table: table}

      checkpoint = %{
        version: 1,
        agent_module: MigrationAgent,
        id: "legacy-identity",
        state: %{__identity__: legacy_identity()},
        thread: nil
      }

      :ok = ETS.put_checkpoint({MigrationAgent, "legacy-identity"}, checkpoint, table: table)

      assert {:ok, restored} = Persist.thaw(storage, MigrationAgent, "legacy-identity")
      assert %Identity{} = restored.state.__identity__
      assert restored.state.__identity__.profile[:origin] == :legacy
    end
  end
end
