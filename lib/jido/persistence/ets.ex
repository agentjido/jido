defmodule Jido.Persistence.ETS do
  @moduledoc """
  In-memory persistence adapter for development and tests.

  Data is lost when the BEAM stops. The `:table` option selects the base table
  name. The default is `:jido_persistence`.
  """

  @behaviour Jido.Persistence.Adapter

  @default_table :jido_persistence

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    table = table(opts)
    ensure_table(table)

    case :ets.lookup(table, key) do
      [{^key, value}] when is_binary(value) -> {:ok, value}
      [{^key, _value}] -> {:error, :invalid_value}
      [] -> {:error, :not_found}
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    table = table(opts)
    ensure_table(table)
    :ets.insert(table, {key, value})
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    table = table(opts)
    ensure_table(table)

    replaced? =
      case expected do
        :not_found -> :ets.insert_new(table, {key, value})
        binary -> :ets.select_replace(table, [{{key, binary}, [], [{:const, {key, value}}]}]) == 1
      end

    if replaced?, do: :ok, else: {:error, :conflict}
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    table = table(opts)
    ensure_table(table)
    :ets.delete(table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp table(opts) do
    case Keyword.get(opts, :table, @default_table) do
      @default_table -> :jido_persistence_records
      base -> :"#{base}_records"
    end
  end

  defp ensure_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        _ =
          :ets.new(
            name,
            [
              :named_table,
              :public,
              :set,
              read_concurrency: true
            ] ++ heir_opts(name)
          )

        :ok

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp heir_opts(name) do
    case Process.whereis(Jido.Supervisor) do
      pid when is_pid(pid) and pid != self() -> [{:heir, pid, {:jido_persistence_ets, name}}]
      _other -> []
    end
  end
end
