Code.require_file("redis.exs", __DIR__)
Code.require_file("postgres.exs", __DIR__)
Code.require_file("minio.exs", __DIR__)

defmodule JidoTest.System.Adapters do
  @moduledoc false
  import ExUnit.Callbacks
  import ExUnit.Assertions
  alias JidoTest.Persistence.{EctoRepo, EctoSupport}
  alias JidoTest.System.RedisServer

  def start!(:ets, _path, _observer) do
    table = :"system_#{System.unique_integer([:positive])}"
    records = :"#{table}_records"
    start_supervised!({Agent, fn -> :ets.new(records, [:named_table, :public, :set]) end})
    {Jido.Persistence.ETS, table: table}
  end

  def start!(:file, path, _observer), do: {Jido.Persistence.File, path: Path.join(path, "files")}

  def start!(:ecto, path, _observer) do
    start_supervised!(
      {EctoRepo, EctoSupport.repo_start_options(Path.join(path, "records.sqlite3"))}
    )

    EctoSupport.migrate!()
    {Jido.Persistence.Ecto, repo: EctoRepo}
  end

  def start!(:postgres, _path, observer) do
    server = start_supervised!({JidoTest.System.Postgres, observer})
    opts = GenServer.call(server, :connection, 30_000)
    repo = JidoTest.System.PostgresRepo
    start_supervised!({repo, opts})
    assert {:ok, %{rows: [[1]]}} = Ecto.Adapters.SQL.query(repo, "SELECT 1", [])
    Ecto.Migrator.up(repo, 20_260_909_01, JidoTest.Persistence.EctoMigration, log: false)
    {Jido.Persistence.Ecto, repo: repo}
  end

  def start!(:redis, path, observer) do
    redis_path = Path.join(path, "redis")
    server = start_supervised!({RedisServer, {redis_path, observer}})
    {socket, _os_pid} = GenServer.call(server, :connection, 10_000)

    on_exit(fn ->
      logs = JidoTest.System.Observability.logs(observer)
      started = for %{meta: %{service: :redis, phase: :started, os_pid: pid}} <- logs, do: pid

      stopped =
        for %{
              meta: %{
                service: :redis,
                exit_status: status,
                expected_exit_status: expected,
                os_pid: pid
              }
            } <- logs do
          assert status == expected

          {_output, alive} =
            System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true)

          assert alive != 0
          pid
        end

      assert started != []
      assert Enum.sort(started) == Enum.sort(stopped)
    end)

    assert RedisServer.command(socket, ["PING"]) == {:ok, "PONG"}
    {Jido.Persistence.Redis, command_fn: &RedisServer.command(socket, &1), prefix: "system"}
  end

  def start!(:s3_minio, _path, observer) do
    JidoTest.System.MinIO.start_s3!(observer, &on_exit/1)
  end

  def start!(adapter, path, observer) when adapter in [:bedrock, :bedrock_minio] do
    storage_opts =
      if adapter == :bedrock_minio,
        do: [object_storage: JidoTest.System.MinIO.start!(observer, &on_exit/1)],
        else: []

    # Give each empty cluster distinct service names. The cluster restart fixture
    # intentionally keeps one cluster identity and its existing data directory.
    suffix = System.unique_integer([:positive])
    cluster = Module.concat(__MODULE__, "Cluster#{suffix}")
    repo = Module.concat(cluster, Repo)

    Code.compile_quoted(
      quote do
        defmodule unquote(cluster) do
          use Bedrock.Cluster, otp_app: :bedrock, name: unquote("jido_system_#{suffix}")
        end

        defmodule unquote(repo) do
          use Bedrock.Repo, cluster: unquote(cluster)
        end
      end
    )

    :ok =
      JidoTest.BedrockIntegration.start!(
        Path.join(path, "bedrock"),
        &on_exit/1,
        [cluster: cluster, repo: repo] ++ storage_opts
      )

    {Jido.Persistence.Bedrock, repo: repo, prefix: "system/", timeout_in_ms: 10_000}
  end
end
