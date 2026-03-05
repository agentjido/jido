defmodule Jido.Storage.Redis do
  @moduledoc """
  Redis-based storage adapter for agent checkpoints and thread journals.

  Durable storage suitable for production. Survives process restarts and
  pod rolls — data persists as long as the Redis server retains it.

  ## Usage

      defmodule MyApp.Jido do
        use Jido,
          otp_app: :my_app,
          storage: {Jido.Storage.Redis, [
            command_fn: fn cmd -> Redix.command(:my_redis, cmd) end,
            prefix: "jido"
          ]}
      end

  ## Options

  - `:command_fn` (required) — A function that executes Redis commands.
    Signature: `fn [String.t()] -> {:ok, term()} | {:error, term()}`
    This avoids adding Redix as a dependency; callers provide their own
    Redis client.
  - `:prefix` (optional, default `"jido"`) — Key prefix for namespacing.
  - `:ttl` (optional) — TTL in milliseconds for all keys. When set, keys
    expire automatically.

  ## Key Layout

      {prefix}:cp:{hex_hash}           → Serialized checkpoint
      {prefix}:th:{thread_id}:entries   → Serialized thread entries
      {prefix}:th:{thread_id}:meta      → Serialized thread metadata

  ## Concurrency

  Thread operations use `:global.trans/3` for distributed locking, matching
  the pattern used by `Jido.Storage.ETS` and `Jido.Storage.File`.
  """

  @behaviour Jido.Storage

  alias Jido.Thread
  alias Jido.Thread.EntryNormalizer

  @default_prefix "jido"

  @type opts :: keyword()

  # =============================================================================
  # Checkpoint Operations
  # =============================================================================

  @impl true
  @spec get_checkpoint(term(), opts()) :: {:ok, term()} | :not_found | {:error, term()}
  def get_checkpoint(key, opts) do
    command_fn = fetch_command_fn!(opts)
    redis_key = checkpoint_key(key, opts)

    case command_fn.(["GET", redis_key]) do
      {:ok, nil} -> :not_found
      {:ok, binary} -> safe_binary_to_term(binary)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec put_checkpoint(term(), term(), opts()) :: :ok | {:error, term()}
  def put_checkpoint(key, data, opts) do
    command_fn = fetch_command_fn!(opts)
    redis_key = checkpoint_key(key, opts)
    binary = :erlang.term_to_binary(data)

    command =
      case Keyword.get(opts, :ttl) do
        nil -> ["SET", redis_key, binary]
        ttl -> ["SET", redis_key, binary, "PX", to_string(ttl)]
      end

    case command_fn.(command) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec delete_checkpoint(term(), opts()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts) do
    command_fn = fetch_command_fn!(opts)
    redis_key = checkpoint_key(key, opts)

    case command_fn.(["DEL", redis_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Thread Operations
  # =============================================================================

  @impl true
  @spec load_thread(String.t(), opts()) :: {:ok, Thread.t()} | :not_found | {:error, term()}
  def load_thread(thread_id, opts) do
    command_fn = fetch_command_fn!(opts)
    entries_key = thread_entries_key(thread_id, opts)
    meta_key = thread_meta_key(thread_id, opts)

    with {:ok, entries_binary} <- command_fn.(["GET", entries_key]),
         {:ok, meta_binary} <- command_fn.(["GET", meta_key]) do
      if is_nil(entries_binary) or is_nil(meta_binary) do
        :not_found
      else
        with {:ok, entries} <- safe_binary_to_term(entries_binary),
             {:ok, meta} <- safe_binary_to_term(meta_binary) do
          {:ok, reconstruct_thread(thread_id, entries, meta)}
        end
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @spec append_thread(String.t(), [term()], opts()) :: {:ok, Thread.t()} | {:error, term()}
  def append_thread(thread_id, entries, opts) do
    expected_rev = Keyword.get(opts, :expected_rev)
    now = System.system_time(:millisecond)

    lock_key = {:jido_storage_redis_append_thread, thread_id}
    lock_id = {lock_key, self()}

    :global.trans(lock_id, fn ->
      do_append_thread(thread_id, entries, expected_rev, now, opts)
    end)
  end

  @impl true
  @spec delete_thread(String.t(), opts()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    command_fn = fetch_command_fn!(opts)
    entries_key = thread_entries_key(thread_id, opts)
    meta_key = thread_meta_key(thread_id, opts)

    case command_fn.(["DEL", entries_key, meta_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp do_append_thread(thread_id, entries, expected_rev, now, opts) do
    command_fn = fetch_command_fn!(opts)
    entries_key = thread_entries_key(thread_id, opts)
    meta_key = thread_meta_key(thread_id, opts)

    {current_rev, current_entries, created_at, metadata} =
      load_thread_or_new(command_fn, entries_key, meta_key)

    with :ok <- validate_expected_rev(expected_rev, current_rev) do
      base_seq = current_rev
      is_new = current_rev == 0

      prepared_entries = EntryNormalizer.normalize_many(entries, base_seq, now)
      all_entries = current_entries ++ prepared_entries
      new_rev = current_rev + length(prepared_entries)

      thread_metadata =
        if is_new do
          Keyword.get(opts, :metadata, metadata)
        else
          metadata
        end

      created_at = if is_new, do: now, else: created_at

      meta = %{
        rev: new_rev,
        created_at: created_at,
        updated_at: now,
        metadata: thread_metadata
      }

      entries_binary = :erlang.term_to_binary(all_entries)
      meta_binary = :erlang.term_to_binary(meta)

      ttl = Keyword.get(opts, :ttl)

      set_entries_cmd =
        case ttl do
          nil -> ["SET", entries_key, entries_binary]
          t -> ["SET", entries_key, entries_binary, "PX", to_string(t)]
        end

      set_meta_cmd =
        case ttl do
          nil -> ["SET", meta_key, meta_binary]
          t -> ["SET", meta_key, meta_binary, "PX", to_string(t)]
        end

      with {:ok, _} <- command_fn.(set_entries_cmd),
           {:ok, _} <- command_fn.(set_meta_cmd) do
        {:ok, reconstruct_thread(thread_id, all_entries, meta)}
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp load_thread_or_new(command_fn, entries_key, meta_key) do
    with {:ok, entries_binary} <- command_fn.(["GET", entries_key]),
         {:ok, meta_binary} <- command_fn.(["GET", meta_key]) do
      if is_nil(entries_binary) or is_nil(meta_binary) do
        {0, [], nil, %{}}
      else
        entries = :erlang.binary_to_term(entries_binary, [:safe])
        meta = :erlang.binary_to_term(meta_binary, [:safe])
        {meta.rev, entries, meta.created_at, meta.metadata}
      end
    else
      {:error, _} -> {0, [], nil, %{}}
    end
  end

  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected_rev, expected_rev), do: :ok
  defp validate_expected_rev(_expected_rev, _current_rev), do: {:error, :conflict}

  defp reconstruct_thread(thread_id, entries, meta) do
    entry_count = length(entries)

    %Thread{
      id: thread_id,
      rev: entry_count,
      entries: entries,
      created_at: meta[:created_at],
      updated_at: meta[:updated_at],
      metadata: meta[:metadata] || %{},
      stats: %{entry_count: entry_count}
    }
  end

  defp checkpoint_key(key, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)
    "#{prefix}:cp:#{hash}"
  end

  defp thread_entries_key(thread_id, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    "#{prefix}:th:#{thread_id}:entries"
  end

  defp thread_meta_key(thread_id, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    "#{prefix}:th:#{thread_id}:meta"
  end

  defp fetch_command_fn!(opts) do
    case Keyword.fetch(opts, :command_fn) do
      {:ok, fun} when is_function(fun, 1) -> fun
      _ -> raise ArgumentError, "Jido.Storage.Redis requires a :command_fn option"
    end
  end

  defp safe_binary_to_term(binary) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError -> {:error, :invalid_term}
  end
end
