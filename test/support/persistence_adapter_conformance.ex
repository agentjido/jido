defmodule JidoTest.Persistence.AdapterConformance do
  @moduledoc false

  import ExUnit.Assertions
  alias Jido.Persistence.Store

  def assert_binary_get_and_cas(adapter, opts, name) do
    assert {:ok, store} = Store.open({adapter, opts})
    key = "#{name}:#{System.unique_integer([:positive])}"
    first = <<0, 255, 1>>
    second = <<2, 0, 3>>

    assert {:error, :not_found} = Store.read(store, key)
    assert :ok = Store.compare_and_swap(store, key, :not_found, first)
    assert {:ok, ^first, first_condition} = Store.read(store, key)
    assert {:error, :conflict} = Store.compare_and_swap(store, key, :not_found, second)
    assert {:ok, ^first, ^first_condition} = Store.read(store, key)
    assert :ok = Store.compare_and_swap(store, key, first_condition, second)
    assert {:error, :conflict} = Store.compare_and_swap(store, key, first_condition, "stale")
    assert {:ok, ^second, second_condition} = Store.read(store, key)

    results =
      1..4
      |> Task.async_stream(
        fn value ->
          bytes = <<value>>
          {Store.compare_and_swap(store, key, second_condition, bytes), bytes}
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 3
    assert {:ok, ^winner, _condition} = Store.read(store, key)

    :ok
  end
end
