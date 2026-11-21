if Code.ensure_loaded?(Ecto.Migration) do
  defmodule Jido.Persistence.Ecto.Migration do
    @moduledoc """
    Creates and removes the default Ecto persistence table.

    The host application owns the migration file and calls this helper from
    `up/0` and `down/0`. Always pin `:version` in that file so a later Jido
    release cannot change an old migration.

        defmodule MyApp.Repo.Migrations.CreateJidoPersistenceRecords do
          use Ecto.Migration

          def up, do: Jido.Persistence.Ecto.Migration.up(version: 1)
          def down, do: Jido.Persistence.Ecto.Migration.down(version: 1)
        end

    Use `:table` with a matching custom Ecto schema. Use `:prefix` with the
    same repository prefix that the persistence adapter uses.
    """

    use Ecto.Migration

    @current_version 1
    @options [:prefix, :table, :version]

    @doc "Returns the latest migration version."
    @spec current_version() :: pos_integer()
    def current_version, do: @current_version

    @doc "Runs migrations through the selected version."
    @spec up(keyword()) :: :ok
    def up(opts \\ []) do
      config = options!(opts)

      for version <- 1..config.version do
        migrate_up(version, config)
      end

      :ok
    end

    @doc "Reverses migrations through the selected version."
    @spec down(keyword()) :: :ok
    def down(opts \\ []) do
      config = options!(opts)

      for version <- config.version..1//-1 do
        migrate_down(version, config)
      end

      :ok
    end

    defp migrate_up(1, config) do
      create table(config.table, table_options(config, primary_key: false)) do
        add(:key, :binary, primary_key: true, null: false)
        add(:value, :binary, null: false)
        add(:write_token, :binary, null: false)
      end
    end

    defp migrate_down(1, config) do
      drop(table(config.table, table_options(config)))
    end

    defp options!(opts) when is_list(opts) do
      unless Keyword.keyword?(opts) do
        raise ArgumentError, "migration options must be a keyword list"
      end

      case Keyword.keys(opts) -- @options do
        [] -> :ok
        unknown -> raise ArgumentError, "unknown migration options: #{inspect(unknown)}"
      end

      version = Keyword.get(opts, :version, @current_version)
      table = Keyword.get(opts, :table, :jido_persistence_records)
      prefix = Keyword.get(opts, :prefix)

      unless is_integer(version) and version >= 1 and version <= @current_version do
        raise ArgumentError,
              "migration version must be between 1 and #{@current_version}, got: #{inspect(version)}"
      end

      unless is_atom(table) and not is_nil(table) do
        raise ArgumentError, "migration table must be a non-nil atom"
      end

      unless is_nil(prefix) or is_binary(prefix) do
        raise ArgumentError, "migration prefix must be a string or nil"
      end

      %{prefix: prefix, table: table, version: version}
    end

    defp options!(opts),
      do: raise(ArgumentError, "migration options must be a keyword list, got: #{inspect(opts)}")

    defp table_options(config, opts \\ []) do
      if config.prefix, do: Keyword.put(opts, :prefix, config.prefix), else: opts
    end
  end
end
