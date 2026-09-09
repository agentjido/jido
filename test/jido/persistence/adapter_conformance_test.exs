defmodule JidoTest.Persistence.AdapterConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence.{ETS, Redis}
  alias Jido.Persistence.File, as: FilePersistence

  test "built-in adapters obey the required binary get and CAS contract" do
    for {name, adapter, opts} <- adapters() do
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
    end
  end

  defp adapters do
    suffix = System.unique_integer([:positive])
    file_path = Path.join(System.tmp_dir!(), "jido-adapter-conformance-#{suffix}")
    Elixir.File.mkdir_p!(file_path)
    on_exit(fn -> Elixir.File.rm_rf!(file_path) end)

    redis_store = start_supervised!({Elixir.Agent, fn -> %{} end}, id: {:redis_store, suffix})

    [
      {:ets, ETS, [table: :"adapter_conformance_#{suffix}"]},
      {:file, FilePersistence, [path: file_path]},
      {:redis, Redis, [command_fn: redis_command(redis_store)]}
    ]
  end

  defp redis_command(store) do
    fn
      ["GET", key] ->
        {:ok, Elixir.Agent.get(store, &Map.get(&1, key))}

      ["EVAL", _script, "1", key, mode, expected, value, _ttl] ->
        Elixir.Agent.get_and_update(store, fn values ->
          current = Map.get(values, key, :not_found)
          wanted = if mode == "missing", do: :not_found, else: expected

          if current == wanted do
            {{:ok, 1}, Map.put(values, key, value)}
          else
            {{:ok, 0}, values}
          end
        end)
    end
  end
end
