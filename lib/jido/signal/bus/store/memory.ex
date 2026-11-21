defmodule Jido.Signal.Bus.Store.Memory do
  @moduledoc """
  In-memory Bus Store.

  Records are indexed by cursor in an OTP `:gb_trees` value. The store keeps a
  bounded log and removes the oldest records that no durable subscription still
  needs. If durable cursors prevent enough removal, `append/2` returns
  `{:error, {:store_full, durable_ids}}` and changes no state.

  This store does not survive a Bus or VM restart.
  """

  @behaviour Jido.Signal.Bus.Store

  alias Jido.Signal.Router
  alias Jido.Signal.Router.{Index, Route}

  @default_max_records 100_000

  @impl true
  def init(opts) do
    max_records = Keyword.get(opts, :max_records, @default_max_records)

    if is_integer(max_records) and max_records > 0 do
      {:ok,
       %{
         records: :gb_trees.empty(),
         subscriptions: %{},
         subscription_order: [],
         latest_cursor: 0,
         max_records: max_records
       }}
    else
      {:error, {:invalid_option, :max_records}}
    end
  end

  @impl true
  def append(records, state) when is_list(records) and is_integer(length(records)) do
    with :ok <- validate_records(records, state.latest_cursor),
         records_tree <- insert_records(state.records, records),
         {:ok, records_tree} <- retain_within_bound(records_tree, state) do
      latest_cursor =
        case List.last(records) do
          nil -> state.latest_cursor
          record -> Map.fetch!(record, "cursor")
        end

      {:ok,
       %{
         state
         | records: records_tree,
           latest_cursor: latest_cursor
       }}
    end
  end

  def append(_records, _state), do: {:error, :invalid_records}

  @impl true
  def read(opts, state) do
    after_cursor = Keyword.get(opts, :after_cursor, 0)
    path = Keyword.get(opts, :path)
    limit = Keyword.get(opts, :limit, :infinity)

    cond do
      not valid_read_options?(after_cursor, path, limit) ->
        {:error, :invalid_read_options}

      not is_nil(path) and Route.validate_path(path, []) != :ok ->
        {:ok, []}

      true ->
        pattern = if is_nil(path), do: nil, else: Index.compile_pattern(path)

        records =
          :gb_trees.iterator_from(after_cursor + 1, state.records)
          |> collect_records(pattern, limit, [])

        {:ok, records}
    end
  end

  @impl true
  def latest_cursor(state), do: {:ok, state.latest_cursor}

  @impl true
  def list_subscriptions(state) do
    {:ok, Enum.map(state.subscription_order, &Map.fetch!(state.subscriptions, &1))}
  end

  @impl true
  def put_subscription(%{"id" => id} = subscription, state) when is_binary(id) do
    with :ok <- validate_subscription(subscription),
         :ok <- validate_subscription_cursor(subscription, state.latest_cursor),
         :ok <- validate_subscription_update(Map.get(state.subscriptions, id), subscription) do
      order =
        if Map.has_key?(state.subscriptions, id) do
          state.subscription_order
        else
          state.subscription_order ++ [id]
        end

      {:ok,
       %{
         state
         | subscriptions: Map.put(state.subscriptions, id, subscription),
           subscription_order: order
       }}
    end
  end

  def put_subscription(_subscription, _state), do: {:error, :invalid_subscription}

  @impl true
  def delete_subscription(id, state) when is_binary(id) do
    {:ok,
     %{
       state
       | subscriptions: Map.delete(state.subscriptions, id),
         subscription_order: Enum.reject(state.subscription_order, &(&1 == id))
     }}
  end

  defp validate_records([], _latest_cursor), do: :ok

  defp validate_records(records, latest_cursor) do
    if Enum.all?(records, &is_map/1) do
      expected = Enum.to_list((latest_cursor + 1)..(latest_cursor + length(records)))
      actual = Enum.map(records, &Map.get(&1, "cursor"))

      cond do
        actual != expected -> {:error, :invalid_record_cursors}
        Enum.all?(records, &valid_record?/1) -> :ok
        true -> {:error, :invalid_records}
      end
    else
      {:error, :invalid_records}
    end
  end

  defp valid_record?(%{
         "format_version" => 1,
         "id" => id,
         "cursor" => cursor,
         "type" => type,
         "created_at" => created_at,
         "signal" => signal
       }) do
    is_binary(id) and is_integer(cursor) and cursor > 0 and is_binary(type) and
      is_binary(created_at) and is_map(signal)
  end

  defp valid_record?(_record), do: false

  defp insert_records(tree, records) do
    Enum.reduce(records, tree, fn record, current_tree ->
      :gb_trees.insert(Map.fetch!(record, "cursor"), record, current_tree)
    end)
  end

  defp valid_read_options?(after_cursor, path, limit) do
    is_integer(after_cursor) and after_cursor >= 0 and
      (is_nil(path) or is_binary(path)) and
      (limit == :infinity or (is_integer(limit) and limit > 0))
  end

  defp collect_records(_iterator, _path, 0, records), do: Enum.reverse(records)

  defp collect_records(iterator, path, limit, records) do
    case :gb_trees.next(iterator) do
      :none ->
        Enum.reverse(records)

      {_cursor, record, next_iterator} ->
        if is_nil(path) or Index.matches_compiled?(Map.fetch!(record, "type"), path) do
          collect_records(next_iterator, path, decrement(limit), [record | records])
        else
          collect_records(next_iterator, path, limit, records)
        end
    end
  end

  defp decrement(:infinity), do: :infinity
  defp decrement(limit), do: limit - 1

  defp validate_subscription(%{
         "format_version" => 1,
         "id" => id,
         "path" => path,
         "cursor" => cursor,
         "created_at" => created_at
       }) do
    if is_binary(id) and byte_size(id) > 0 and is_binary(path) and
         is_integer(cursor) and cursor >= 0 and is_binary(created_at) do
      :ok
    else
      {:error, :invalid_subscription}
    end
  end

  defp validate_subscription(_subscription), do: {:error, :invalid_subscription}

  defp validate_subscription_cursor(subscription, latest_cursor) do
    if subscription["cursor"] <= latest_cursor,
      do: :ok,
      else: {:error, :invalid_subscription_cursor}
  end

  defp validate_subscription_update(nil, _subscription), do: :ok

  defp validate_subscription_update(existing, subscription) do
    cond do
      existing["path"] != subscription["path"] ->
        {:error, :subscription_conflict}

      existing["created_at"] != subscription["created_at"] ->
        {:error, :subscription_conflict}

      existing["cursor"] > subscription["cursor"] ->
        {:error, :cursor_regression}

      true ->
        :ok
    end
  end

  defp retain_within_bound(records, %{subscriptions: subscriptions} = state)
       when map_size(subscriptions) == 0 do
    remove_count = max(:gb_trees.size(records) - state.max_records, 0)
    {:ok, remove_oldest(records, remove_count)}
  end

  defp retain_within_bound(records, state) do
    remove_count = max(:gb_trees.size(records) - state.max_records, 0)

    case releasable_cursors(records, state.subscriptions, remove_count) do
      {:ok, cursors} ->
        retained = Enum.reduce(cursors, records, &:gb_trees.delete_any/2)
        {:ok, retained}

      :full ->
        {:error, {:store_full, blocking_subscription_ids(records, state.subscriptions)}}
    end
  end

  defp remove_oldest(records, 0), do: records

  defp remove_oldest(records, count) do
    {_cursor, _record, retained} = :gb_trees.take_smallest(records)
    remove_oldest(retained, count - 1)
  end

  defp releasable_cursors(_records, _subscriptions, 0), do: {:ok, []}

  defp releasable_cursors(records, subscriptions, count) do
    records
    |> :gb_trees.iterator()
    |> collect_releasable_cursors(subscriptions, count, [])
  end

  defp collect_releasable_cursors(_iterator, _subscriptions, 0, cursors) do
    {:ok, Enum.reverse(cursors)}
  end

  defp collect_releasable_cursors(iterator, subscriptions, remaining, cursors) do
    case :gb_trees.next(iterator) do
      :none ->
        :full

      {cursor, record, next_iterator} ->
        if releasable?(record, subscriptions) do
          collect_releasable_cursors(next_iterator, subscriptions, remaining - 1, [
            cursor | cursors
          ])
        else
          collect_releasable_cursors(next_iterator, subscriptions, remaining, cursors)
        end
    end
  end

  defp releasable?(record, subscriptions) do
    not Enum.any?(subscriptions, fn {_id, subscription} ->
      subscription_needs_record?(subscription, record)
    end)
  end

  defp subscription_needs_record?(subscription, record) do
    Map.fetch!(record, "cursor") > Map.fetch!(subscription, "cursor") and
      Router.matches?(Map.fetch!(record, "type"), Map.fetch!(subscription, "path"))
  end

  defp blocking_subscription_ids(records, subscriptions) do
    retained_records = :gb_trees.values(records)

    subscriptions
    |> Enum.filter(fn {_id, subscription} ->
      Enum.any?(retained_records, &subscription_needs_record?(subscription, &1))
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end
end
