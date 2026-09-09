defmodule JidoTest.Persistence.AdapterConformance do
  @moduledoc false

  import ExUnit.Assertions

  def assert_binary_get_and_cas(adapter, opts, name) do
    key = "#{name}:#{System.unique_integer([:positive])}"
    first = <<0, 255, 1>>
    second = <<2, 0, 3>>

    assert {:error, :not_found} = adapter.get(key, opts)
    assert :ok = adapter.compare_and_swap(key, :not_found, first, opts)
    assert {:ok, ^first} = adapter.get(key, opts)
    assert {:error, :conflict} = adapter.compare_and_swap(key, :not_found, second, opts)
    assert {:error, :conflict} = adapter.compare_and_swap(key, <<99>>, second, opts)
    assert {:ok, ^first} = adapter.get(key, opts)
    assert :ok = adapter.compare_and_swap(key, first, second, opts)
    assert {:ok, ^second} = adapter.get(key, opts)

    results =
      1..4
      |> Task.async_stream(
        fn value ->
          bytes = <<value>>
          {adapter.compare_and_swap(key, second, bytes, opts), bytes}
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
    assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 3
    assert {:ok, ^winner} = adapter.get(key, opts)

    :ok
  end
end
