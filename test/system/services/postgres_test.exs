Code.require_file("support/docker.exs", __DIR__)

defmodule JidoTest.System.Services.PostgresTest do
  use JidoTest.Case, async: false

  @moduletag :service
  @moduletag timeout: 120_000

  use JidoTest.Persistence.Contracts.Store

  defmodule Repo do
    use Ecto.Repo, otp_app: :jido, adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    container =
      JidoTest.System.Services.Docker.start!(
        "postgres:17-alpine",
        5432,
        [
          env: [
            POSTGRES_PASSWORD: "jido-system-only",
            POSTGRES_DB: "jido_system"
          ]
        ],
        &on_exit/1
      )

    start_supervised!(
      {Repo,
       hostname: "127.0.0.1",
       port: container.port,
       username: "postgres",
       password: "jido-system-only",
       database: "jido_system",
       pool_size: 4,
       log: false}
    )

    eventually(
      fn ->
        case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
          {:ok, %{rows: [[1]]}} -> true
          _other -> nil
        end
      end,
      timeout: 30_000
    )

    Ecto.Migrator.up(Repo, 20_260_909_01, Jido.Persistence.Ecto.Migration, log: false)
    {:ok, store: {Jido.Persistence.Ecto, repo: Repo}}
  end
end
