defmodule Jido.Persistence.FileTest do
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
        1..2
        |> Task.async_stream(
          fn n ->
            value = <<round, n>>
            {FilePersistence.compare_and_swap("key", expected, value, opts), value}
          end,
          max_concurrency: 2,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{:ok, winner}] = Enum.filter(results, &match?({:ok, _}, &1))
      assert Enum.count(results, &match?({{:error, :conflict}, _}, &1)) == 1
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

  test "scans binary records by prefix in stable pages", %{opts: opts} do
    assert :ok = FilePersistence.put("agent:b", <<2>>, opts)
    assert :ok = FilePersistence.put("other:a", <<0>>, opts)
    assert :ok = FilePersistence.put("agent:a", <<1>>, opts)

    assert Enum.sort(scan_all("agent:", opts, 1)) == [
             {"agent:a", <<1>>},
             {"agent:b", <<2>>}
           ]
  end

  test "scan cursors bound work for binary key prefixes", %{opts: opts} do
    prefix = <<0, 255>>
    first_key = prefix <> <<0>>
    second_key = prefix <> <<1>>

    assert :ok = FilePersistence.put(first_key, <<1>>, opts)
    assert :ok = FilePersistence.put(second_key, <<2>>, opts)
    assert :ok = FilePersistence.put("unrelated", <<3>>, opts)

    assert Enum.sort(scan_all(prefix, opts, 1)) == [
             {first_key, <<1>>},
             {second_key, <<2>>}
           ]

    assert {:error, :invalid_scan_cursor} = FilePersistence.scan(prefix, "not a cursor", 1, opts)

    assert :ok = FilePersistence.delete(first_key, opts)
    assert scan_all(prefix, opts, 1) == [{second_key, <<2>>}]
  end

  test "validates required keyword options" do
    assert :ok = FilePersistence.validate_options(path: "/tmp/jido")
    assert {:error, _reason} = FilePersistence.validate_options([])
    assert {:error, _reason} = FilePersistence.validate_options(path: "")
    assert {:error, _reason} = FilePersistence.validate_options([:not_keyword])
  end

  defp scan_all(prefix, opts, limit, cursor \\ nil, entries \\ []) do
    assert {:ok, page, next_cursor} = FilePersistence.scan(prefix, cursor, limit, opts)
    entries = entries ++ page

    if is_nil(next_cursor),
      do: entries,
      else: scan_all(prefix, opts, limit, next_cursor, entries)
  end
end
