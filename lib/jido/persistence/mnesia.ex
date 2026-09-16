defmodule Jido.Persistence.Mnesia do
  @moduledoc """
  Mnesia byte adapter for `Jido.Persistence.Store`.

  The required `:table` option names an existing `set` table with attributes
  `[:key, :value]`. The application starts Mnesia and owns the schema, table,
  copies, disk policy, and recovery. This adapter does not create a table or
  start Mnesia. A `local_content` table is not supported.

  Reads and writes use Mnesia transactions. A compare-and-swap takes a write
  lock on the key and commits the comparison and replacement together.
  Mnesia transaction aborts return an error. The Store treats an unclassified
  write error as indeterminate, so a record owner must reload before retrying.
  """

  @behaviour Jido.Persistence.Adapter

  @impl true
  @spec validate_options(keyword()) :: :ok | {:error, term()}
  def validate_options(opts) do
    with true <- is_list(opts) and Keyword.keyword?(opts),
         [:table] <- Keyword.keys(opts),
         table when is_atom(table) and not is_nil(table) <- Keyword.get(opts, :table),
         [:key, :value] <- :mnesia.table_info(table, :attributes),
         :set <- :mnesia.table_info(table, :type),
         false <- :mnesia.table_info(table, :local_content),
         :ok <- :mnesia.wait_for_tables([table], 5_000) do
      :ok
    else
      _ -> {:error, :invalid_mnesia_options}
    end
  catch
    :exit, reason -> {:error, {:mnesia_unavailable, reason}}
  end

  @impl true
  @spec get(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  def get(key, opts) when is_binary(key) do
    with :ok <- validate_options(opts) do
      transaction(fn -> read_value(Keyword.fetch!(opts, :table), key) end)
    end
  end

  @impl true
  @spec put(binary(), binary(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts) when is_binary(key) and is_binary(value) do
    with :ok <- validate_options(opts) do
      transaction(fn -> :mnesia.write({Keyword.fetch!(opts, :table), key, value}) end)
    end
  end

  @impl true
  @spec compare_and_swap(binary(), binary() | :not_found, binary(), keyword()) ::
          :ok | {:error, term()}
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and is_binary(value) do
    with :ok <- validate_options(opts) do
      transaction(fn -> swap_value(Keyword.fetch!(opts, :table), key, expected, value) end)
    end
  end

  @impl true
  @spec delete(binary(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts) when is_binary(key) do
    with :ok <- validate_options(opts) do
      transaction(fn -> :mnesia.delete({Keyword.fetch!(opts, :table), key}) end)
    end
  end

  defp read_value(table, key) do
    case :mnesia.read(table, key, :read) do
      [{^table, ^key, value}] when is_binary(value) -> {:ok, value}
      [] -> {:error, :not_found}
      _ -> {:error, :invalid_value}
    end
  end

  defp swap_value(table, key, expected, value) do
    case {:mnesia.read(table, key, :write), expected} do
      {[], :not_found} ->
        :mnesia.write({table, key, value})

      {[{^table, ^key, ^expected}], expected} when is_binary(expected) ->
        :mnesia.write({table, key, value})

      _ ->
        {:error, :conflict}
    end
  end

  defp transaction(fun) do
    if :mnesia.is_transaction() do
      {:error, {:rejected, :nested_transaction}}
    else
      case :mnesia.transaction(fun) do
        {:atomic, result} -> result
        {:aborted, reason} -> {:error, {:mnesia_aborted, reason}}
      end
    end
  end
end
