defmodule JidoTest.StorageCheckpointConformance do
  @moduledoc """
  Reusable ExUnit cases for the checkpoint half of `Jido.Storage`.

  The caller supplies the adapter module and an option expression. The
  expression is evaluated separately for every generated test, so adapters
  can create isolated tables, directories, or other test resources without
  becoming part of the shared contract.

  ## Example

      use JidoTest.StorageCheckpointConformance,
        adapter: Jido.Storage.ETS,
        setup: quote do: [table: unique_table(:checkpoint_contract)]

  The helper intentionally covers only checkpoint semantics. Thread behavior,
  adapter lifecycle, and backend-specific error handling remain in the
  adapter's own test module.
  """

  defmacro __using__(options) do
    adapter = Keyword.fetch!(options, :adapter)

    setup =
      case Keyword.get(options, :setup, quote(do: [])) do
        {:quote, _, [[do: expression]]} -> expression
        expression -> expression
      end

    quote do
      alias unquote(adapter), as: CheckpointStorageAdapter

      describe "checkpoint storage conformance" do
        test "returns :not_found for a missing checkpoint" do
          opts = unquote(setup)

          assert :not_found =
                   CheckpointStorageAdapter.get_checkpoint(
                     {:missing, make_ref()},
                     opts
                   ),
                 "checkpoint contract: missing get must return :not_found"
        end

        test "stores and retrieves a checkpoint" do
          opts = unquote(setup)
          key = {:roundtrip, make_ref()}
          value = %{state: :saved, nested: [1, %{two: 2}]}

          assert :ok = CheckpointStorageAdapter.put_checkpoint(key, value, opts),
                 "checkpoint contract: put must return :ok"

          assert {:ok, ^value} = CheckpointStorageAdapter.get_checkpoint(key, opts),
                 "checkpoint contract: get must return the stored value"
        end

        test "overwrites a checkpoint for the same key" do
          opts = unquote(setup)
          key = {:overwrite, make_ref()}

          assert :ok = CheckpointStorageAdapter.put_checkpoint(key, :first, opts),
                 "checkpoint contract: initial put must return :ok"

          assert :ok = CheckpointStorageAdapter.put_checkpoint(key, :second, opts),
                 "checkpoint contract: overwrite put must return :ok"

          assert {:ok, :second} = CheckpointStorageAdapter.get_checkpoint(key, opts),
                 "checkpoint contract: latest value must replace the previous value"
        end

        test "preserves arbitrary term keys and values" do
          opts = unquote(setup)

          values = [
            {"string", {:tuple, %{nested: [:term, 42]}}},
            {{:tuple, 7, self()}, %MapSet{} |> MapSet.put(:value)},
            {42, {:atom, [nil, false, %{binary: <<1, 2, 3>>}]}}
          ]

          Enum.each(values, fn {key, value} ->
            assert :ok = CheckpointStorageAdapter.put_checkpoint(key, value, opts),
                   "checkpoint contract: arbitrary term key #{inspect(key)} must be storable"

            assert {:ok, ^value} = CheckpointStorageAdapter.get_checkpoint(key, opts),
                   "checkpoint contract: arbitrary term key #{inspect(key)} must round-trip"
          end)
        end

        test "deletes an existing checkpoint" do
          opts = unquote(setup)
          key = {:delete, make_ref()}

          assert :ok = CheckpointStorageAdapter.put_checkpoint(key, :present, opts),
                 "checkpoint contract: setup put must return :ok"

          assert :ok = CheckpointStorageAdapter.delete_checkpoint(key, opts),
                 "checkpoint contract: delete must return :ok"

          assert :not_found = CheckpointStorageAdapter.get_checkpoint(key, opts),
                 "checkpoint contract: deleted key must be missing"
        end

        test "deleting a missing checkpoint is idempotent" do
          opts = unquote(setup)
          key = {:delete_missing, make_ref()}

          assert :ok = CheckpointStorageAdapter.delete_checkpoint(key, opts),
                 "checkpoint contract: deleting a missing key must return :ok"

          assert :ok = CheckpointStorageAdapter.delete_checkpoint(key, opts),
                 "checkpoint contract: repeated delete must remain :ok"
        end
      end
    end
  end
end
