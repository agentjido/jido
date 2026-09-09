if Code.ensure_loaded?(Ecto.Schema) do
  defmodule Jido.Persistence.Ecto.Record do
    @moduledoc """
    Default schema for `Jido.Persistence.Ecto`.

    The host application owns the matching database migration. The table has
    one row for each binary Jido storage key. `write_token` is private adapter
    data. It makes a successful same-value compare-and-swap change a physical
    column, so affected-row counts stay reliable.
    """

    use Ecto.Schema

    @primary_key {:key, :binary, autogenerate: false}
    schema "jido_persistence_records" do
      field(:value, :binary)
      field(:write_token, :binary)
    end
  end
end

if Code.ensure_loaded?(Ecto.Query) and Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule Jido.Persistence.Ecto.Implementation do
    @moduledoc false

    @behaviour Jido.Persistence.Adapter

    @default_schema Jido.Persistence.Ecto.Record
    @supported_adapters [
      :"Elixir.Ecto.Adapters.Postgres",
      :"Elixir.Ecto.Adapters.SQLite3"
    ]
    @required_schema_fields MapSet.new([:key, :value, :write_token])
    @reserved_repo_options [:conflict_target, :on_conflict]

    import Ecto.Query, only: [from: 2]

    @impl true
    def validate_options(opts) do
      with :ok <- validate_keyword_options(opts),
           {:ok, repo} <- fetch_repo(opts),
           {:ok, _adapter} <- validate_repo(repo),
           {:ok, schema} <- fetch_schema(opts),
           :ok <- validate_schema(schema),
           :ok <- validate_repo_options(Keyword.get(opts, :repo_options, [])) do
        :ok
      end
    end

    @impl true
    def get(key, opts) when is_binary(key) and is_list(opts) do
      validate_options!(opts)
      repo = Keyword.fetch!(opts, :repo)
      schema = Keyword.get(opts, :schema, @default_schema)

      protect_operation(fn ->
        case repo.get(schema, key, repo_options(opts)) do
          nil ->
            {:error, :not_found}

          %{value: value} when is_binary(value) ->
            {:ok, value}

          result ->
            {:error, {:invalid_ecto_result, result}}
        end
      end)
    end

    @impl true
    def put(key, value, opts)
        when is_binary(key) and is_binary(value) and is_list(opts) do
      validate_options!(opts)
      repo = Keyword.fetch!(opts, :repo)
      schema = Keyword.get(opts, :schema, @default_schema)
      records = [record_attributes(key, value)]

      protect_operation(fn ->
        case repo.insert_all(schema, records, upsert_options(opts)) do
          {1, _returned} -> :ok
          result -> {:error, {:invalid_ecto_result, result}}
        end
      end)
    end

    @impl true
    def compare_and_swap(key, expected, value, opts)
        when is_binary(key) and (expected == :not_found or is_binary(expected)) and
               is_binary(value) and is_list(opts) do
      validate_options!(opts)

      protect_write(fn ->
        case expected do
          :not_found -> insert_missing(key, value, opts)
          expected_value -> update_expected(key, expected_value, value, opts)
        end
      end)
    end

    @impl true
    def delete(key, opts) when is_binary(key) and is_list(opts) do
      validate_options!(opts)
      repo = Keyword.fetch!(opts, :repo)
      schema = Keyword.get(opts, :schema, @default_schema)
      query = from(record in schema, where: field(record, :key) == ^key)

      protect_operation(fn ->
        case repo.delete_all(query, repo_options(opts)) do
          {count, _returned} when is_integer(count) and count >= 0 -> :ok
          result -> {:error, {:invalid_ecto_result, result}}
        end
      end)
    end

    defp insert_missing(key, value, opts) do
      repo = Keyword.fetch!(opts, :repo)
      schema = Keyword.get(opts, :schema, @default_schema)
      records = [record_attributes(key, value)]

      case repo.insert_all(schema, records, insert_options(opts)) do
        {1, _returned} -> :ok
        {0, _returned} -> {:error, :conflict}
        result -> {:error, {:indeterminate, {:invalid_ecto_result, result}}}
      end
    end

    defp update_expected(key, expected, value, opts) do
      repo = Keyword.fetch!(opts, :repo)
      schema = Keyword.get(opts, :schema, @default_schema)

      query =
        from(record in schema,
          where: field(record, :key) == ^key and field(record, :value) == ^expected
        )

      updates = [set: [value: value, write_token: write_token()]]

      case repo.update_all(query, updates, repo_options(opts)) do
        {1, _returned} -> :ok
        {0, _returned} -> {:error, :conflict}
        result -> {:error, {:indeterminate, {:invalid_ecto_result, result}}}
      end
    end

    defp record_attributes(key, value),
      do: %{key: key, value: value, write_token: write_token()}

    defp insert_options(opts) do
      Keyword.merge(repo_options(opts), on_conflict: :nothing, conflict_target: [:key])
    end

    defp upsert_options(opts) do
      Keyword.merge(repo_options(opts),
        on_conflict: {:replace, [:value, :write_token]},
        conflict_target: [:key]
      )
    end

    defp validate_keyword_options(opts) do
      cond do
        not Keyword.keyword?(opts) ->
          {:error, "options must be a keyword list"}

        Enum.any?(Keyword.keys(opts), &(&1 not in [:repo, :schema, :repo_options])) ->
          {:error, "supports only :repo, :schema, and :repo_options options"}

        true ->
          :ok
      end
    end

    defp fetch_repo(opts) do
      case Keyword.fetch(opts, :repo) do
        {:ok, repo} when is_atom(repo) -> {:ok, repo}
        _other -> {:error, "requires a :repo module"}
      end
    end

    defp validate_repo(repo) do
      with {:module, ^repo} <- Code.ensure_loaded(repo),
           true <- function_exported?(repo, :__adapter__, 0),
           adapter when adapter in @supported_adapters <- repo.__adapter__(),
           true <- function_exported?(repo, :get, 3),
           true <- function_exported?(repo, :insert_all, 3),
           true <- function_exported?(repo, :update_all, 3),
           true <- function_exported?(repo, :delete_all, 2) do
        {:ok, adapter}
      else
        adapter when is_atom(adapter) ->
          {:error, "Ecto adapter #{inspect(adapter)} is not supported"}

        _other ->
          {:error, ":repo must implement Ecto.Repo with a supported SQL adapter"}
      end
    rescue
      error -> {:error, ":repo validation failed: #{Exception.message(error)}"}
    catch
      kind, reason -> {:error, ":repo validation failed: #{inspect({kind, reason})}"}
    end

    defp fetch_schema(opts) do
      case Keyword.get(opts, :schema, @default_schema) do
        schema when is_atom(schema) -> {:ok, schema}
        _other -> {:error, ":schema must be an Ecto schema module"}
      end
    end

    defp validate_schema(schema) do
      with {:module, ^schema} <- Code.ensure_loaded(schema),
           true <- function_exported?(schema, :__schema__, 1),
           [:key] <- schema.__schema__(:primary_key),
           :binary <- schema.__schema__(:type, :key),
           :binary <- schema.__schema__(:type, :value),
           :binary <- schema.__schema__(:type, :write_token),
           fields <- MapSet.new(schema.__schema__(:fields)),
           true <- MapSet.equal?(fields, @required_schema_fields) do
        :ok
      else
        _other ->
          {:error,
           ":schema must have only a binary :key primary key and binary :value and :write_token fields"}
      end
    rescue
      error -> {:error, ":schema validation failed: #{Exception.message(error)}"}
    catch
      kind, reason -> {:error, ":schema validation failed: #{inspect({kind, reason})}"}
    end

    defp validate_repo_options(repo_options) do
      cond do
        not Keyword.keyword?(repo_options) ->
          {:error, ":repo_options must be a keyword list"}

        Enum.any?(@reserved_repo_options, &Keyword.has_key?(repo_options, &1)) ->
          {:error, ":repo_options cannot set :on_conflict or :conflict_target"}

        true ->
          :ok
      end
    end

    defp repo_options(opts), do: Keyword.get(opts, :repo_options, [])

    defp write_token, do: :crypto.strong_rand_bytes(16)

    defp protect_operation(fun) do
      fun.()
    rescue
      error -> {:error, ecto_failure(:error, error)}
    catch
      kind, reason -> {:error, ecto_failure(kind, reason)}
    end

    defp protect_write(fun) do
      fun.()
    rescue
      error -> {:error, {:indeterminate, ecto_failure(:error, error)}}
    catch
      kind, reason -> {:error, {:indeterminate, ecto_failure(kind, reason)}}
    end

    defp ecto_failure(:error, error) do
      {:ecto, error.__struct__, Exception.message(error)}
    end

    defp ecto_failure(kind, reason), do: {:ecto, kind, reason}

    defp validate_options!(opts) do
      case validate_options(opts) do
        :ok -> :ok
        {:error, reason} -> raise ArgumentError, "Jido.Persistence.Ecto #{reason}"
      end
    end
  end
end

defmodule Jido.Persistence.Ecto do
  @moduledoc """
  Ecto SQL persistence adapter for binary keys and values.

  This adapter keeps the `Jido.Persistence.Adapter` byte contract. It does not
  decode checkpoints or change Jido record semantics. The required `:repo`
  option selects a running Ecto repository. The optional `:schema` defaults to
  `Jido.Persistence.Ecto.Record`. The optional `:repo_options` keyword list is
  sent to repository calls and can contain options such as `:prefix` and
  `:timeout`.

  The schema must use `:key` as its single `:binary` primary key. It must also
  have `:value` and `:write_token` fields of type `:binary`. It must have no
  other stored fields. The database must enforce `NOT NULL` for all three
  columns. The adapter supports PostgreSQL and SQLite Ecto adapters.

  The repository database role must have direct select, insert, update, and
  delete access to the table. Do not add a trigger or rule that hides a row,
  suppresses a write, or changes `key`, `value`, or `write_token`. Such database
  behavior makes the affected-row result unsuitable for CAS.

  Compare-and-swap uses one `INSERT` for an absent expected value or one
  conditional `UPDATE` for expected bytes. It never implements CAS as a read
  followed by a write. Database or connection failures during CAS have an
  indeterminate result.

  Ecto SQL is an optional dependency. Add `:ecto_sql` and the database driver
  to the host application. The adapter reports invalid configuration when Ecto
  SQL was not present while Jido compiled.

  The host application must create the table before it starts a Jido instance
  that uses this adapter. The adapter does not run migrations. This migration
  supports the default schema on PostgreSQL and SQLite:

      defmodule MyApp.Repo.Migrations.CreateJidoPersistenceRecords do
        use Ecto.Migration

        def change do
          create table(:jido_persistence_records, primary_key: false) do
            add :key, :binary, primary_key: true, null: false
            add :value, :binary, null: false
            add :write_token, :binary, null: false
          end
        end
      end

  Configure an instance with the supervised application repository:

      use Jido,
        otp_app: :my_app,
        persistence: {Jido.Persistence.Ecto, repo: MyApp.Repo}

  Use `repo_options: [prefix: "tenant"]` for an Ecto query prefix. To use a
  different table, supply a custom Ecto schema that has the exact required
  fields and set it with `:schema`.
  """

  @behaviour Jido.Persistence.Adapter

  @implementation Jido.Persistence.Ecto.Implementation
  @unavailable "requires the optional :ecto_sql dependency at compile time"

  @impl true
  def validate_options(opts) do
    if Code.ensure_loaded?(@implementation) do
      apply(@implementation, :validate_options, [opts])
    else
      {:error, @unavailable}
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts),
    do: call_or_unavailable!(:get, [key, opts])

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts),
    do: call_or_unavailable!(:put, [key, value, opts])

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts),
      do: call_or_unavailable!(:compare_and_swap, [key, expected, value, opts])

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts),
    do: call_or_unavailable!(:delete, [key, opts])

  defp call_or_unavailable!(function, arguments) do
    if Code.ensure_loaded?(@implementation) do
      apply(@implementation, function, arguments)
    else
      raise ArgumentError, "Jido.Persistence.Ecto #{@unavailable}"
    end
  end
end
