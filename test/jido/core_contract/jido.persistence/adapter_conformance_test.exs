defmodule JidoTest.Persistence.AdapterConformanceTest do
  use Covenant.Case, component: "jido.persistence", async: false

  alias Jido.Persistence.{Ecto, ETS, Mnesia, Redis, S3}
  alias Jido.Persistence.File, as: FilePersistence

  alias JidoTest.Persistence.{
    AdapterConformance,
    EctoRepo,
    EctoSupport,
    Profiles,
    S3Client
  }

  @tag obligation: "jido.persistence.I15"
  test "built-in adapters obey the required binary get and CAS contract" do
    adapters = adapters()

    assert Profiles.discovered_adapter_modules() == Profiles.adapter_modules()
    assert MapSet.new(adapters, &elem(&1, 1)) == Profiles.active_adapter_modules()

    for {name, adapter, opts} <- adapters do
      assert :ok = AdapterConformance.assert_binary_get_and_cas(adapter, opts, name)
    end
  end

  defp adapters do
    suffix = "#{System.pid()}-#{System.unique_integer([:positive])}"
    file_path = Path.join(System.tmp_dir!(), "jido-adapter-conformance-#{suffix}")
    Elixir.File.mkdir_p!(file_path)
    on_exit(fn -> Elixir.File.rm_rf!(file_path) end)

    redis_store = start_supervised!({Elixir.Agent, fn -> %{} end}, id: {:redis_store, suffix})

    ecto_path = EctoSupport.database_path(:conformance)
    start_supervised!({EctoRepo, EctoSupport.repo_start_options(ecto_path)})
    EctoSupport.migrate!()
    on_exit(fn -> EctoSupport.remove_database(ecto_path) end)

    {:ok, _started} = Application.ensure_all_started(:mnesia)
    mnesia_table = :"adapter_conformance_mnesia_#{suffix}"

    {:atomic, :ok} =
      :mnesia.create_table(mnesia_table, attributes: [:key, :value], ram_copies: [node()])

    on_exit(fn ->
      case :mnesia.delete_table(mnesia_table) do
        {:atomic, :ok} -> :ok
        {:aborted, {:no_exists, ^mnesia_table}} -> :ok
      end
    end)

    s3_store = start_supervised!({Elixir.Agent, fn -> %{} end}, id: {:s3_store, suffix})

    [
      {:ets, ETS, [table: :"adapter_conformance_#{suffix}"]},
      {:file, FilePersistence, [path: file_path]},
      {:mnesia, Mnesia, [table: mnesia_table]},
      {:redis, Redis, [command_fn: redis_command(redis_store)]},
      {:ecto, Ecto, [repo: EctoRepo]},
      {:s3, S3, [bucket: "jido-test", prefix: "contract/", request_fn: S3Client.new(s3_store)]}
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
