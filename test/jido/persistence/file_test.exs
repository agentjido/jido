defmodule JidoTest.Persistence.FileTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence.File, as: FilePersistence

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido_file_persistence_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, opts: [path: path]}
  end

  test "conditional writes require the exact bytes or an absent key", %{opts: opts} do
    assert {:error, :conflict} = FilePersistence.compare_and_swap("key", <<0>>, <<1>>, opts)
    assert :ok = FilePersistence.compare_and_swap("key", :not_found, <<0, 255>>, opts)
    assert {:error, :conflict} = FilePersistence.compare_and_swap("key", :not_found, <<1>>, opts)
    assert {:error, :conflict} = FilePersistence.compare_and_swap("key", <<0>>, <<1>>, opts)
    assert {:ok, <<0, 255>>} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.compare_and_swap("key", <<0, 255>>, <<1>>, opts)
    assert {:ok, <<1>>} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.delete("key", opts)
    assert {:error, :conflict} = FilePersistence.compare_and_swap("key", <<1>>, <<2>>, opts)
  end

  test "one concurrent writer wins for each expected value", %{opts: opts} do
    for {expected, round} <- [{:not_found, 1}, {<<0, 255>>, 2}] do
      if round == 2, do: assert(:ok = FilePersistence.put("key", expected, opts))

      results =
        1..8
        |> Task.async_stream(
          fn n ->
            value = <<round, n>>
            {FilePersistence.compare_and_swap("key", expected, value, opts), value}
          end,
          max_concurrency: 8,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 7
      assert {:ok, ^winner} = FilePersistence.get("key", opts)
    end
  end

  test "gets, replaces, and deletes binary values", %{opts: opts} do
    assert {:error, :not_found} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.put("key", <<1>>, opts)
    assert {:ok, <<1>>} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.put("key", <<2>>, opts)
    assert {:ok, <<2>>} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.delete("key", opts)
    assert {:error, :not_found} = FilePersistence.get("key", opts)
    assert :ok = FilePersistence.delete("key", opts)
  end

  test "supports binary keys and values", %{opts: opts} do
    key = "agent/id with spaces"
    value = <<0, 1, 2, 3, 255>>

    assert :ok = FilePersistence.put(key, value, opts)
    assert {:ok, ^value} = FilePersistence.get(key, opts)
  end
end
