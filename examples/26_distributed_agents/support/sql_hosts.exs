Code.require_file("sql_repos.ex", __DIR__)

defmodule Jido.Examples.DistributedAgents.StoreMigration do
  @moduledoc false
  use Ecto.Migration

  def up, do: Jido.Persistence.Ecto.Migration.up(version: 1)
end

defmodule Jido.Examples.DistributedAgents.SqlHosts do
  @moduledoc false

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]
  import Jido.Test.AgentServer.PeerCase, only: [peer_call: 4]

  alias Jido.Examples.DistributedAgents.{PeerHosts, PostgresRepo, SqliteRepo, StoreMigration}

  @repo_source Path.expand("sql_repos.ex", __DIR__)

  def open(peers, tmp_dir) do
    {repo, driver, opts, prefix} = settings(tmp_dir)
    migration_opts = if prefix, do: [prefix: prefix, log: false], else: [log: false]
    {:ok, _} = Application.ensure_all_started(driver)

    with_repo(repo, opts, fn ->
      if prefix do
        Ecto.Adapters.SQL.query!(repo, "CREATE SCHEMA " <> prefix)
        on_exit(fn -> drop_schema(repo, opts, prefix) end)
      end

      :ok = Ecto.Migrator.up(repo, 1, StoreMigration, migration_opts)
    end)

    PeerHosts.load(peers, [@repo_source])

    for peer <- peers do
      assert {:ok, _} = peer_call(peer, Application, :ensure_all_started, [driver])
      assert {:ok, _} = peer_call(peer, Supervisor, :start_child, [Jido.Supervisor, {repo, opts}])
      assert {:ok, %{rows: [[1]]}} = peer_call(peer, Ecto.Adapters.SQL, :query, [repo, "SELECT 1", []])
    end

    repo_options = if prefix, do: [prefix: prefix], else: []
    {Jido.Persistence.Ecto, repo: repo, repo_options: repo_options}
  end

  defp settings(tmp_dir) do
    case System.get_env("JIDO_EXAMPLE_POSTGRES_URL") do
      nil ->
        {SqliteRepo, :ecto_sqlite3,
         [
           database: Path.join(tmp_dir, "tickets.sqlite3"),
           pool_size: 2,
           busy_timeout: 5_000,
           journal_mode: :wal,
           log: false
         ], nil}

      "" ->
        raise ArgumentError, "JIDO_EXAMPLE_POSTGRES_URL must point to a disposable PostgreSQL database"

      url ->
        suffix = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
        {PostgresRepo, :postgrex, [url: url, pool_size: 2, log: false], "jido_example_" <> suffix}
    end
  end

  defp drop_schema(repo, opts, prefix) do
    with_repo(repo, opts, fn -> Ecto.Adapters.SQL.query!(repo, "DROP SCHEMA " <> prefix <> " CASCADE") end)
  end

  defp with_repo(repo, opts, operation) do
    {:ok, pid} = repo.start_link(opts)

    try do
      operation.()
    after
      Supervisor.stop(pid)
    end
  end
end
