defmodule JidoCoreBench.PersistenceCases do
  @moduledoc false
  alias JidoCoreBench.Fixtures, as: F
  alias Jido.Persistence.ETS, as: Store

  def workloads do
    for {scope, options} <- [
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
end
