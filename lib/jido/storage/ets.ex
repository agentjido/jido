defmodule Jido.Storage.ETS do
  @moduledoc """
  ETS-based storage adapter for agent checkpoints and thread journals.

  Fast in-memory storage for development and testing. Not restart-safe -
  all data is lost when the BEAM stops.

  ## Usage

      defmodule MyApp.Jido do
        use Jido,
          otp_app: :my_app,
          storage: {Jido.Storage.ETS, table: :my_jido_storage}
      end

  ## Options

  - `:table` - Base table name (default: `:jido_storage`). Creates three tables:
    - `{table, :checkpoints}` - Agent checkpoint data (set)
    - `{table, :threads}` - Thread entries ordered by `{thread_id, seq}` (ordered_set)
    - `{table, :thread_meta}` - Thread metadata (set)

  ## Concurrency

  Thread operations use atomic ETS operations. The `expected_rev` option in
  `append_thread/3` provides optimistic concurrency control.
  """

  @behaviour Jido.Storage

  alias Jido.Thread
  alias Jido.Thread.Entry

  @default_table :jido_storage

  @type opts :: keyword()

  @impl true
  @doc """
  Retrieve a checkpoint by key.

  Returns `{:ok, data}` if found, `:not_found` otherwise.
  """
  @spec get_checkpoint(term(), opts()) :: {:ok, term()} | :not_found | {:error, term()}
  def get_checkpoint(key, opts) do
    table = checkpoint_table(opts)
    ensure_tables(opts)

    case :ets.lookup(table, key) do
      [{^key, data}] -> {:ok, data}
      [] -> :not_found
    end
  rescue
    ArgumentError -> :not_found
  end

  @impl true
  @doc """
  Store a checkpoint, overwriting any existing value.
  """
  @spec put_checkpoint(term(), term(), opts()) :: :ok | {:error, term()}
  def put_checkpoint(key, data, opts) do
    table = checkpoint_table(opts)
    ensure_tables(opts)
    :ets.insert(table, {key, data})
    :ok
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  @doc """
  Delete a checkpoint by key.
  """
  @spec delete_checkpoint(term(), opts()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts) do
    table = checkpoint_table(opts)
    ensure_tables(opts)
    :ets.delete(table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @impl true
  @doc """
  Load a thread by ID, reconstructing from stored entries.

  Returns `{:ok, thread}` if entries exist, `:not_found` otherwise.
  """
  @spec load_thread(String.t(), opts()) :: {:ok, Thread.t()} | :not_found | {:error, term()}
  def load_thread(thread_id, opts) do
    threads_table = threads_table(opts)
    meta_table = meta_table(opts)
    ensure_tables(opts)

    entries =
      :ets.select(threads_table, [
        {{{thread_id, :_}, :_}, [], [:"$_"]}
      ])
      |> Enum.sort_by(fn {{_id, seq}, _entry} -> seq end)
      |> Enum.map(fn {_key, entry} -> entry end)

    case entries do
      [] ->
        :not_found

      entries ->
        meta = get_thread_meta(meta_table, thread_id)
        {:ok, reconstruct_thread(thread_id, entries, meta)}
    end
  rescue
    ArgumentError -> :not_found
  end

  @impl true
  @doc """
  Append entries to a thread.

  ## Options

  - `:expected_rev` - If provided, the append will fail with `{:error, :conflict}`
    if the current thread revision doesn't match.
  - `:metadata` - Thread metadata to merge (only used when creating new thread).
  """
  @spec append_thread(String.t(), [Entry.t()], opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def append_thread(thread_id, entries, opts) do
    threads_table = threads_table(opts)
    meta_table = meta_table(opts)
    ensure_tables(opts)

    expected_rev = Keyword.get(opts, :expected_rev)
    now = System.system_time(:millisecond)

    current_rev = get_current_rev(threads_table, thread_id)

    if expected_rev && current_rev != expected_rev do
      {:error, :conflict}
    else
      base_seq = current_rev
      is_new = current_rev == 0

      prepared_entries =
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, idx} ->
          seq = base_seq + idx
          prepare_entry(entry, seq, now)
        end)

      ets_entries =
        Enum.map(prepared_entries, fn entry ->
          {{thread_id, entry.seq}, entry}
        end)

      :ets.insert(threads_table, ets_entries)

      meta =
        if is_new do
          new_meta = %{
            created_at: now,
            updated_at: now,
            metadata: Keyword.get(opts, :metadata, %{})
          }

          :ets.insert(meta_table, {thread_id, new_meta})
          new_meta
        else
          update_thread_meta(meta_table, thread_id, now)
        end

      {:ok, reconstruct_thread(thread_id, load_all_entries(threads_table, thread_id), meta)}
    end
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  @doc """
  Delete a thread and all its entries.
  """
  @spec delete_thread(String.t(), opts()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    threads_table = threads_table(opts)
    meta_table = meta_table(opts)
    ensure_tables(opts)

    :ets.select_delete(threads_table, [
      {{{thread_id, :_}, :_}, [], [true]}
    ])

    :ets.delete(meta_table, thread_id)

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp checkpoint_table(opts) do
    base = Keyword.get(opts, :table, @default_table)
    :"#{base}_checkpoints"
  end

  defp threads_table(opts) do
    base = Keyword.get(opts, :table, @default_table)
    :"#{base}_threads"
  end

  defp meta_table(opts) do
    base = Keyword.get(opts, :table, @default_table)
    :"#{base}_thread_meta"
  end

  defp ensure_tables(opts) do
    ensure_table(checkpoint_table(opts), [:set])
    ensure_table(threads_table(opts), [:ordered_set])
    ensure_table(meta_table(opts), [:set])
  end

  defp ensure_table(name, extra_opts) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:named_table, :public, read_concurrency: true] ++ extra_opts)

      _ref ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp get_current_rev(table, thread_id) do
    case :ets.select_reverse(table, [{{{thread_id, :"$1"}, :_}, [], [:"$1"]}], 1) do
      {[seq], _cont} -> seq + 1
      :"$end_of_table" -> 0
    end
  end

  defp load_all_entries(table, thread_id) do
    :ets.select(table, [
      {{{thread_id, :_}, :"$1"}, [], [:"$1"]}
    ])
    |> Enum.sort_by(& &1.seq)
  end

  defp get_thread_meta(table, thread_id) do
    case :ets.lookup(table, thread_id) do
      [{^thread_id, meta}] -> meta
      [] -> %{created_at: nil, updated_at: nil, metadata: %{}}
    end
  end

  defp update_thread_meta(table, thread_id, now) do
    case :ets.lookup(table, thread_id) do
      [{^thread_id, meta}] ->
        updated = %{meta | updated_at: now}
        :ets.insert(table, {thread_id, updated})
        updated

      [] ->
        meta = %{created_at: now, updated_at: now, metadata: %{}}
        :ets.insert(table, {thread_id, meta})
        meta
    end
  end

  defp prepare_entry(%Entry{} = entry, seq, now) do
    %Entry{
      id: entry.id || generate_entry_id(),
      seq: seq,
      at: entry.at || now,
      kind: entry.kind,
      payload: entry.payload,
      refs: entry.refs
    }
  end

  defp prepare_entry(attrs, seq, now) when is_map(attrs) do
    %Entry{
      id: fetch_entry_attr(attrs, :id, &generate_entry_id/0),
      seq: seq,
      at: fetch_entry_attr(attrs, :at, fn -> now end),
      kind: fetch_entry_attr(attrs, :kind, fn -> :note end),
      payload: fetch_entry_attr(attrs, :payload, fn -> %{} end),
      refs: fetch_entry_attr(attrs, :refs, fn -> %{} end)
    }
  end

  defp fetch_entry_attr(attrs, key, default_fun) when is_function(default_fun, 0) do
    case Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key)) do
      nil -> default_fun.()
      value -> value
    end
  end

  defp reconstruct_thread(thread_id, entries, meta) do
    entry_count = length(entries)

    %Thread{
      id: thread_id,
      rev: entry_count,
      entries: entries,
      created_at: meta[:created_at] || (List.first(entries) && List.first(entries).at),
      updated_at: meta[:updated_at] || (List.last(entries) && List.last(entries).at),
      metadata: meta[:metadata] || %{},
      stats: %{entry_count: entry_count}
    }
  end

  defp generate_entry_id do
    "entry_" <> Jido.Util.generate_id()
  end
end
