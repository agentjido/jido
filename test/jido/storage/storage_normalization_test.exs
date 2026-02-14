defmodule JidoTest.StorageNormalizationTest do
  use ExUnit.Case, async: true

  alias Jido.Storage
  alias Jido.Storage.ETS
  alias Jido.Thread

  defp unique_table(test_name) do
    :"test_storage_norm_#{test_name}_#{System.unique_integer([:positive])}"
  end

  describe "fetch_checkpoint/3" do
    test "normalizes :not_found to {:error, :not_found}" do
      opts = [table: unique_table(:checkpoint_missing)]

      assert {:error, :not_found} = Storage.fetch_checkpoint(ETS, :missing_key, opts)
    end

    test "returns checkpoint data on success" do
      opts = [table: unique_table(:checkpoint_success)]
      :ok = ETS.put_checkpoint(:my_key, %{state: :ok}, opts)

      assert {:ok, %{state: :ok}} = Storage.fetch_checkpoint(ETS, :my_key, opts)
    end
  end

  describe "fetch_thread/3" do
    test "normalizes :not_found to {:error, :not_found}" do
      opts = [table: unique_table(:thread_missing)]

      assert {:error, :not_found} = Storage.fetch_thread(ETS, "thread-missing", opts)
    end

    test "returns thread on success" do
      opts = [table: unique_table(:thread_success)]
      thread_id = "thread_#{System.unique_integer([:positive])}"

      assert {:ok, _thread} = ETS.append_thread(thread_id, [%{kind: :note}], opts)
      assert {:ok, %Thread{id: ^thread_id}} = Storage.fetch_thread(ETS, thread_id, opts)
    end
  end
end
