defmodule JidoTest.Persistence.EctoRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :jido,
    adapter: Ecto.Adapters.SQLite3
end

defmodule JidoTest.Persistence.EctoMigration do
  @moduledoc false

  use Ecto.Migration

  def change do
    create table(:jido_persistence_records, primary_key: false) do
      add(:key, :binary, primary_key: true, null: false)
      add(:value, :binary, null: false)
      add(:write_token, :binary, null: false)
    end

    create table(:constrained_jido_persistence_records, primary_key: false) do
      add(:key, :binary, primary_key: true, null: false)
      add(:value, :binary, null: false)
      add(:write_token, :binary, null: false)
    end

    create(unique_index(:constrained_jido_persistence_records, [:value]))
  end
end

defmodule JidoTest.Persistence.EctoSupport do
  @moduledoc false

  alias JidoTest.Persistence.{EctoMigration, EctoRepo}

  def database_path(name) do
    suffix = System.unique_integer([:positive, :monotonic])
    Path.join(System.tmp_dir!(), "jido-ecto-#{name}-#{suffix}.sqlite3")
  end

  def repo_start_options(path) do
    [
      database: path,
      pool_size: 4,
      busy_timeout: 5_000,
      journal_mode: :wal,
      log: false
    ]
  end

  def migrate! do
    Ecto.Migrator.up(EctoRepo, 20_260_909_01, EctoMigration, log: false)
  end

  def remove_database(path) do
    for suffix <- ["", "-shm", "-wal"] do
      File.rm(path <> suffix)
    end

    :ok
  end
end
