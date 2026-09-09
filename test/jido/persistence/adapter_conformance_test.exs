defmodule JidoTest.Persistence.AdapterConformanceTest do
  use ExUnit.Case, async: false

  alias Jido.Persistence.{Ecto, ETS, Redis}
  alias Jido.Persistence.File, as: FilePersistence
  alias JidoTest.Persistence.{AdapterConformance, EctoRepo, EctoSupport}

  test "built-in adapters obey the required binary get and CAS contract" do
    for {name, adapter, opts} <- adapters() do
      assert :ok = AdapterConformance.assert_binary_get_and_cas(adapter, opts, name)
    end
  end

  defp adapters do
    suffix = System.unique_integer([:positive])
    file_path = Path.join(System.tmp_dir!(), "jido-adapter-conformance-#{suffix}")
    Elixir.File.mkdir_p!(file_path)
    on_exit(fn -> Elixir.File.rm_rf!(file_path) end)

    redis_store = start_supervised!({Elixir.Agent, fn -> %{} end}, id: {:redis_store, suffix})

    ecto_path = EctoSupport.database_path(:conformance)
    start_supervised!({EctoRepo, EctoSupport.repo_start_options(ecto_path)})
    EctoSupport.migrate!()
    on_exit(fn -> EctoSupport.remove_database(ecto_path) end)

    [
      {:ets, ETS, [table: :"adapter_conformance_#{suffix}"]},
      {:file, FilePersistence, [path: file_path]},
      {:redis, Redis, [command_fn: redis_command(redis_store)]},
      {:ecto, Ecto, [repo: EctoRepo]}
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
