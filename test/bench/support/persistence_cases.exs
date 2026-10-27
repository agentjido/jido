defmodule JidoCoreBench.PersistenceCases do
  @moduledoc false
  alias Jido.AgentServer.DurableTurn.CheckpointStore
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.Persistence.ETS, as: Store

  def workloads do
    ets_workloads() ++ checkpoint_workloads()
  end

  defp ets_workloads do
    for {scope, options} <-
          [
            default: [],
            explicit_default: [table: :jido_persistence],
            custom: [table: :core_bench_persistence]
          ],
        operation <- [:get, :put, :cas, :conflict] do
      F.checked(
        "persistence/ets/#{scope}/#{operation}/100",
        fn _ ->
          key = "core-bench-#{System.unique_integer([:positive, :monotonic])}"
          :ok = Store.put(key, <<0, 255>>, options)
          {key, options}
        end,
        fn {key, options} ->
          for _ <- 1..100 do
            case operation do
              :get -> Store.get(key, options)
              :put -> Store.put(key, <<0, 255>>, options)
              :cas -> Store.compare_and_swap(key, <<0, 255>>, <<0, 255>>, options)
              :conflict -> Store.compare_and_swap(key, <<1>>, <<2>>, options)
            end
          end
        end,
        fn results ->
          expected =
            case operation do
              :get -> {:ok, <<0, 255>>}
              :conflict -> {:error, :conflict}
              _ -> :ok
            end

          F.equal!(results, List.duplicate(expected, 100))
        end
      )
      |> Map.put(:verify, fn {key, options}, _ ->
        F.equal!(Store.get(key, options), {:ok, <<0, 255>>})
      end)
      |> Map.put(:cleanup, fn {key, options} ->
        :ok = Store.delete(key, options)
        F.equal!(Store.get(key, options), {:error, :not_found})
      end)
    end
  end

  defp checkpoint_workloads do
    [
      F.checked(
        "persistence/checkpoint/32",
        fn _ ->
          id =
            {:jido_execution, Jido.namespace(JidoCoreBench), "bench", "checkpoint",
             System.unique_integer([:positive, :monotonic])}

          config = {Store, table: :core_bench_checkpoint}
          :ok = CheckpointStore.register(JidoCoreBench, id, config)

          %{id: id, batches: checkpoint_batches()}
        end,
        fn prepared ->
          batch_counts =
            Enum.map(prepared.batches, fn batch ->
              {:ok, batch_count} = CheckpointStore.append(prepared.id, batch, JidoCoreBench)
              batch_count
            end)

          {batch_counts, :ets.tab2list(:core_bench_checkpoint_records)}
        end,
        fn {batch_counts, records} ->
          F.equal!(batch_counts, Enum.to_list(1..32))
          F.equal!(length(records), 33)
        end,
        fn _prepared, {_batch_counts, records} ->
          checkpoint_bytes = for {_key, bytes} <- records, into: <<>>, do: bytes
          %{checkpoint_bytes: checkpoint_bytes}
        end
      )
      |> Map.put(:cleanup, fn prepared ->
        :ok = CheckpointStore.collect(JidoCoreBench, prepared.id)

        if :ets.whereis(:core_bench_checkpoint_records) != :undefined,
          do: :ets.delete_all_objects(:core_bench_checkpoint_records)
      end)
    ]
  end

  defp checkpoint_batches do
    event = %{payload: :binary.copy(<<"checkpoint-data">>, 1_024)}
    List.duplicate([event], 32)
  end
end
