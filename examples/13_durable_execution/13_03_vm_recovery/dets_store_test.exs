Code.require_file("support/dets_store.ex", __DIR__)
Code.require_file("vm_recovery.ex", __DIR__)

defmodule Jido.Examples.Durable.DetsStoreTest do
  use Jido.Test.Case, async: false
  @moduletag :integration

  @moduletag :tmp_dir
  alias Jido.Examples.Durable.VMRecovery.DetsStore

  test "conditional bytes survive reopen and corrupt records are rejected", c do
    table = __MODULE__.Checkpoints
    opts = [table: table, path: Path.join(c.tmp_dir, "store.dets")]
    adapter = [server: table]
    start_supervised!({DetsStore, opts})
    assert {:error, :not_found} = DetsStore.get("key", adapter)
    assert :ok = DetsStore.compare_and_swap("key", :not_found, "one", adapter)
    assert {:error, :conflict} = DetsStore.compare_and_swap("key", :not_found, "two", adapter)
    assert :ok = DetsStore.compare_and_swap("key", "one", "two", adapter)
    stop_supervised!(DetsStore)
    assert :dets.info(table) == :undefined
    start_supervised!({DetsStore, opts})
    assert {:ok, "two"} = DetsStore.get("key", adapter)
    assert :ok = :dets.insert(table, {"bad", :invalid})

    assert {:error, :invalid_value} =
             DetsStore.compare_and_swap("bad", :not_found, "new", adapter)

    stop_supervised!(DetsStore)
    assert :dets.info(table) == :undefined
  end
end
