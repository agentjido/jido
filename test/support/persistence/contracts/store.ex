defmodule JidoTest.Persistence.Contracts.Store do
  @moduledoc false

  defmacro __using__(_opts) do
    quote location: :keep do
      alias Jido.Persistence.Store

      @tag persistence_contract: :store
      test "store reads, creates, updates, and rejects stale conditions", c do
        assert {:ok, store} = Store.open(c.store)
        key = "store-contract:#{unique_id()}"
        first = <<0, 255, 1>>
        second = <<2, 0, 3>>

        assert {:error, :not_found} = Store.read(store, key)
        assert :ok = Store.compare_and_swap(store, key, :not_found, first)
        assert {:ok, ^first, condition} = Store.read(store, key)
        assert :ok = Store.compare_and_swap(store, key, condition, second)
        assert {:error, :conflict} = Store.compare_and_swap(store, key, condition, "stale")
        assert {:ok, ^second, _condition} = Store.read(store, key)
      end

      @tag persistence_contract: :store
      test "one concurrent writer wins for one read condition", c do
        assert {:ok, store} = Store.open(c.store)
        key = "store-race:#{unique_id()}"
        assert :ok = Store.compare_and_swap(store, key, :not_found, "base")
        assert {:ok, "base", condition} = Store.read(store, key)

        results =
          1..4
          |> Task.async_stream(
            fn value ->
              bytes = :erlang.term_to_binary(value)
              {Store.compare_and_swap(store, key, condition, bytes), bytes}
            end,
            max_concurrency: 4,
            timeout: 10_000
          )
          |> Enum.map(fn {:ok, result} -> result end)

        assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _bytes}, &1))
        assert Enum.count(results, &match?({{:error, :conflict}, _bytes}, &1)) == 3
        assert {:ok, ^winner, _condition} = Store.read(store, key)
      end
    end
  end
end
