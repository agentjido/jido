defmodule Jido.Persistence.ETS do
  @moduledoc """
  In-memory persistence adapter for development and tests.

  With the Jido application running, tables survive their creator's exit by
  transferring to a supervised owner. Inherited tables are lost when that owner
  or the application stops. Without the application, tables end with their creator.
  All data is lost when the BEAM stops.

  The `:table` option selects the base table name. The default is `:jido_persistence`.
  """

  @behaviour Jido.Persistence.Store

  @default_table :jido_persistence

  @impl true
  def validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) -> {:error, "options must be a keyword list"}
      Keyword.keys(opts) -- [:table] != [] -> {:error, "supports only the :table option"}
      Keyword.keys(opts) -- Enum.uniq(Keyword.keys(opts)) != [] -> {:error, "options must be unique"}
      not is_atom(Keyword.get(opts, :table, @default_table)) -> {:error, ":table must be an atom"}
      true -> :ok
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)
    table = table(opts)
    ensure_table(table)

    case :ets.lookup(table, key) do
      [{^key, value}] when is_binary(value) -> {:ok, value}
      [{^key, _value}] -> {:error, :invalid_value}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    validate_options!(opts)
    table = table(opts)
    ensure_table(table)
    :ets.insert(table, {key, value})
    :ok
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    validate_options!(opts)
    table = table(opts)
    ensure_table(table)

    replaced? =
      case expected do
        :not_found -> :ets.insert_new(table, {key, value})
        binary -> :ets.select_replace(table, [{{key, binary}, [], [{:const, {key, value}}]}]) == 1
      end

    if replaced?, do: :ok, else: {:error, :conflict}
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)
    table = table(opts)
    ensure_table(table)
    :ets.delete(table, key)
    :ok
  end

  @impl true
  def scan(prefix, cursor, limit, opts)
      when is_binary(prefix) and (is_nil(cursor) or is_binary(cursor)) and is_integer(limit) and
             limit > 0 and is_list(opts) do
    validate_options!(opts)
    table = table(opts)
    ensure_table(table)

    with :ok <- require_ordered_set(table),
         {:ok, entries} <- collect_page(table, prefix, first_key(table, prefix, cursor), limit + 1, []) do
      page = Enum.take(entries, limit)
      next_cursor = if length(entries) > limit, do: page |> List.last() |> elem(0), else: nil
      {:ok, page, next_cursor}
    end
  end

  defp validate_options!(opts) do
    case validate_options(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "Jido.Persistence.ETS #{reason}"
    end
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
              :ordered_set,
              read_concurrency: true
            ] ++ heir_opts(name)
          )

        :ok

      _ref ->
        :ok
    end
  rescue
    error in ArgumentError ->
      if :ets.whereis(name) == :undefined, do: reraise(error, __STACKTRACE__), else: :ok
  end

  defp heir_opts(name) do
    case Process.whereis(Jido.Persistence.ETS.Owner) do
      pid when is_pid(pid) and pid != self() -> [{:heir, pid, {:jido_persistence_ets, name}}]
      _other -> []
    end
  end

  defp require_ordered_set(table) do
    if :ets.info(table, :type) == :ordered_set, do: :ok, else: {:error, :scan_requires_ordered_set}
  end

  defp first_key(table, prefix, nil) do
    case :ets.lookup(table, prefix) do
      [{^prefix, _value}] -> prefix
      [] -> :ets.next(table, prefix)
    end
  end

  defp first_key(table, _prefix, cursor), do: :ets.next(table, cursor)

  defp collect_page(_table, _prefix, _key, 0, entries), do: {:ok, Enum.reverse(entries)}
  defp collect_page(_table, _prefix, :"$end_of_table", _remaining, entries), do: {:ok, Enum.reverse(entries)}

  defp collect_page(table, prefix, key, remaining, entries) when is_binary(key) do
    if binary_prefix?(key, prefix) do
      case :ets.lookup(table, key) do
        [{^key, value}] when is_binary(value) ->
          collect_page(table, prefix, :ets.next(table, key), remaining - 1, [{key, value} | entries])

        [{^key, _value}] ->
          {:error, :invalid_value}

        [] ->
          collect_page(table, prefix, :ets.next(table, key), remaining, entries)
      end
    else
      {:ok, Enum.reverse(entries)}
    end
  end

  defp collect_page(_table, _prefix, _key, _remaining, entries), do: {:ok, Enum.reverse(entries)}

  defp binary_prefix?(value, prefix) do
    prefix_size = byte_size(prefix)
    byte_size(value) >= prefix_size and binary_part(value, 0, prefix_size) == prefix
  end
end
