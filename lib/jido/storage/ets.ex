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

  ## Table Ownership Policy

  Tables are created through `Jido.Storage.ETS.Owner`, with
  `Jido.Storage.ETS.Heir` configured as ETS heir. This avoids accidental table
  loss when a random caller process exits.
  """

  @behaviour Jido.Storage

  alias Jido.Storage.ETS.Owner
  alias Jido.Thread
  alias Jido.Thread.Entry

  @default_table :jido_storage

  @type opts :: keyword()

  @impl true
  @doc """
  Retrieve a checkpoint by key.

  Returns `{:ok, data}` if found, `{:error, :not_found}` otherwise.
  """
  @spec get_checkpoint(term(), opts()) :: {:ok, term()} | {:error, :not_found | term()}
  def get_checkpoint(key, opts) do
    with {:ok, table} <- checkpoint_table(opts),
         :ok <- ensure_tables(opts) do
      case :ets.lookup(table, key) do
        [{^key, data}] -> {:ok, data}
        [] -> {:error, :not_found}
      end
    end
  rescue
    ArgumentError -> {:error, :not_found}
  end

  @impl true
  @doc """
  Store a checkpoint, overwriting any existing value.
  """
  @spec put_checkpoint(term(), term(), opts()) :: :ok | {:error, term()}
  def put_checkpoint(key, data, opts) do
    with {:ok, table} <- checkpoint_table(opts),
         :ok <- ensure_tables(opts) do
      :ets.insert(table, {key, data})
      :ok
    end
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  @impl true
  @doc """
  Delete a checkpoint by key.
  """
  @spec delete_checkpoint(term(), opts()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts) do
    with {:ok, table} <- checkpoint_table(opts),
         :ok <- ensure_tables(opts) do
      :ets.delete(table, key)
      :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @impl true
  @doc """
  Load a thread by ID, reconstructing from stored entries.

  Returns `{:ok, thread}` if entries exist, `{:error, :not_found}` otherwise.
  """
  @spec load_thread(String.t(), opts()) :: {:ok, Thread.t()} | {:error, :not_found | term()}
  def load_thread(thread_id, opts) do
    with {:ok, threads_table} <- threads_table(opts),
         {:ok, meta_table} <- meta_table(opts),
         :ok <- ensure_tables(opts) do
      entries =
        :ets.select(threads_table, [
          {{{thread_id, :_}, :_}, [], [:"$_"]}
        ])
        |> Enum.sort_by(fn {{_id, seq}, _entry} -> seq end)
        |> Enum.map(fn {_key, entry} -> entry end)

      case entries do
        [] ->
          {:error, :not_found}

        entries ->
          meta = get_thread_meta(meta_table, thread_id)
          {:ok, thread_from_entries(thread_id, entries, meta)}
      end
    end
  rescue
    ArgumentError -> {:error, :not_found}
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
    with {:ok, threads_table} <- threads_table(opts),
         :ok <- ensure_tables(opts) do
      run_locked_append(thread_id, entries, opts, threads_table)
    end
  rescue
    ArgumentError -> {:error, :table_not_found}
  end

  defp do_append_thread(thread_id, entries, opts) do
    {:ok, threads_table} = threads_table(opts)
    {:ok, meta_table} = meta_table(opts)
    expected_rev = Keyword.get(opts, :expected_rev)
    now = System.system_time(:millisecond)

    current_rev = get_current_rev(threads_table, thread_id)

    if expected_rev && current_rev != expected_rev do
      {:error, :conflict}
    else
      base_seq = current_rev
      is_new = current_rev == 0

      prepared_entries =
        Thread.prepare_entries(entries, base_seq, now)

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

      {:ok, thread_from_entries(thread_id, load_all_entries(threads_table, thread_id), meta)}
    end
  end

  @impl true
  @doc """
  Delete a thread and all its entries.
  """
  @spec delete_thread(String.t(), opts()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    with {:ok, threads_table} <- threads_table(opts),
         {:ok, meta_table} <- meta_table(opts),
         :ok <- ensure_tables(opts) do
      :ets.select_delete(threads_table, [
        {{{thread_id, :_}, :_}, [], [true]}
      ])

      :ets.delete(meta_table, thread_id)

      :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Deletes all ETS tables for a storage base name.

  This is primarily intended for tests or explicit lifecycle cleanup.
  """
  @spec cleanup(opts()) :: :ok | {:error, term()}
  def cleanup(opts) do
    with {:ok, checkpoints} <- checkpoint_table(opts),
         {:ok, threads} <- threads_table(opts),
         {:ok, meta} <- meta_table(opts) do
      [checkpoints, threads, meta]
      |> Enum.each(&delete_table_if_exists/1)

      :ok
    end
  end

  defp checkpoint_table(opts) do
    with {:ok, base} <- table_base(opts) do
      {:ok, :"#{base}_checkpoints"}
    end
  end

  defp threads_table(opts) do
    with {:ok, base} <- table_base(opts) do
      {:ok, :"#{base}_threads"}
    end
  end

  defp meta_table(opts) do
    with {:ok, base} <- table_base(opts) do
      {:ok, :"#{base}_thread_meta"}
    end
  end

  defp table_base(opts) do
    case Keyword.get(opts, :table, @default_table) do
      base when is_atom(base) -> {:ok, base}
      _ -> {:error, :invalid_table_name}
    end
  end

  defp ensure_tables(opts) do
    with {:ok, checkpoints} <- checkpoint_table(opts),
         {:ok, threads} <- threads_table(opts),
         {:ok, meta} <- meta_table(opts),
         :ok <- Owner.ensure_table(checkpoints, [:set]),
         :ok <- Owner.ensure_table(threads, [:ordered_set]) do
      Owner.ensure_table(meta, [:set])
    end
  end

  defp run_locked_append(thread_id, entries, opts, threads_table) do
    # :global.trans/2 expects {resource_id, requester_id}. The resource part must stay
    # stable for contention, while requester_id tracks lock ownership per caller pid.
    lock_key = {{__MODULE__, threads_table, thread_id}, self()}

    case :global.trans(lock_key, fn -> do_append_thread(thread_id, entries, opts) end) do
      {:aborted, reason} -> {:error, reason}
      result -> result
    end
  end

  defp delete_table_if_exists(name) when is_atom(name) do
    case :ets.whereis(name) do
      :undefined -> :ok
      _table_ref -> :ets.delete(name)
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

  defp thread_from_entries(thread_id, entries, meta) do
    Thread.from_entries(thread_id, entries,
      metadata: meta[:metadata] || %{},
      created_at: meta[:created_at],
      updated_at: meta[:updated_at]
    )
  end
end
