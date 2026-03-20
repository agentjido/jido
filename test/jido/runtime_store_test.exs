defmodule JidoTest.RuntimeStoreTest do
  use JidoTest.Case, async: true

  alias Jido.RuntimeStore

  describe "RuntimeStore" do
    test "supports put/get/fetch/delete within a hive", %{jido: jido} do
      assert :error == RuntimeStore.fetch(jido, :relationships, "child-1")
      assert nil == RuntimeStore.get(jido, :relationships, "child-1")
      assert :missing == RuntimeStore.get(jido, :relationships, "child-1", :missing)

      assert :ok ==
               RuntimeStore.put(jido, :relationships, "child-1", %{
                 parent_id: "parent-1",
                 tag: :worker
               })

      assert {:ok, %{parent_id: "parent-1", tag: :worker}} =
               RuntimeStore.fetch(jido, :relationships, "child-1")

      assert %{parent_id: "parent-1", tag: :worker} ==
               RuntimeStore.get(jido, :relationships, "child-1")

      assert :ok == RuntimeStore.delete(jido, :relationships, "child-1")
      assert :error == RuntimeStore.fetch(jido, :relationships, "child-1")
    end

    test "keeps hives isolated", %{jido: jido} do
      assert :ok == RuntimeStore.put(jido, :relationships, "child-1", %{parent_id: "parent-1"})
      assert :ok == RuntimeStore.put(jido, :runtime_flags, :orphan_mode, true)

      assert [orphan_mode: true] == Enum.sort(RuntimeStore.list(jido, :runtime_flags))
      assert [{"child-1", %{parent_id: "parent-1"}}] == RuntimeStore.list(jido, :relationships)
    end

    test "retains entries when the RuntimeStore process restarts", %{jido: jido} do
      runtime_store = Jido.runtime_store_name(jido)
      runtime_store_pid = Process.whereis(runtime_store)
      runtime_store_ref = Process.monitor(runtime_store_pid)

      assert :ok ==
               RuntimeStore.put(jido, :relationships, "child-1", %{
                 parent_id: "parent-1",
                 tag: :worker
               })

      Process.exit(runtime_store_pid, :kill)
      assert_receive {:DOWN, ^runtime_store_ref, :process, ^runtime_store_pid, :killed}, 1_000

      eventually(fn ->
        case Process.whereis(runtime_store) do
          pid when is_pid(pid) -> pid != runtime_store_pid
          _ -> false
        end
      end)

      assert {:ok, %{parent_id: "parent-1", tag: :worker}} =
               RuntimeStore.fetch(jido, :relationships, "child-1")
    end
  end
end
