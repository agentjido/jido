defmodule Jido.Storage.Redis do
  @moduledoc """
  Redis-based storage adapter for agent checkpoints and thread journals.

  Durable storage suitable when you already operate Redis and want an
  optional external backing store for Jido. The adapter does not depend
  on a Redis client; callers provide a 1-arity `:command_fn`.

  ## Usage

      defmodule MyApp.RedisStorage do
        def command(cmd), do: Redix.command(:my_redis, cmd)
      end

      defmodule MyApp.Jido do
        use Jido,
          otp_app: :my_app,
          storage: {Jido.Storage.Redis, [
            command_fn: &MyApp.RedisStorage.command/1,
            prefix: "jido"
          ]}
      end

  ## Options

  - `:command_fn` (required) — A function that executes Redis commands.
    Signature: `fn [binary()] -> {:ok, term()} | {:error, term()}`
    This keeps Redis client choice in the caller.
  - `:prefix` (optional, default `"jido"`) — Key prefix for namespacing.
  - `:ttl` (optional) — TTL in milliseconds for all keys. When set, keys
    expire automatically.

  ## Key Layout

      {prefix}:cp:{hex_hash}   → Serialized checkpoint
      {prefix}:th:{thread_id}  → Serialized thread state

  Thread journals are stored as a single serialized value containing
  revision, timestamps, metadata, and entries. Using one key avoids
  partial writes between thread entries and metadata.

  ## Concurrency

  Thread operations use `:global.trans/3` for distributed locking, matching
  the pattern used by `Jido.Storage.ETS` and `Jido.Storage.File`.
  """

  @behaviour Jido.Storage

  alias Jido.Thread
  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer

  @default_prefix "jido"

  @type opts :: keyword()
  @type stored_thread :: %{
          rev: non_neg_integer(),
          created_at: integer(),
          updated_at: integer(),
          metadata: map(),
          entries: [Entry.t()]
        }

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
    redis_key = thread_key(thread_id, opts)

    case command_fn.(["GET", redis_key]) do
      {:ok, nil} ->
        :not_found

      {:ok, binary} ->
        with {:ok, stored_thread} <- decode_thread(binary) do
          {:ok, reconstruct_thread(thread_id, stored_thread)}
        end

      {:error, reason} ->
        {:error, reason}
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
    redis_key = thread_key(thread_id, opts)

    case command_fn.(["DEL", redis_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp do_append_thread(thread_id, entries, expected_rev, now, opts) do
    command_fn = fetch_command_fn!(opts)
    redis_key = thread_key(thread_id, opts)

    with {:ok, stored_thread} <- load_thread_or_new(command_fn, redis_key, now),
         :ok <- validate_expected_rev(expected_rev, stored_thread.rev) do
      base_seq = stored_thread.rev
      is_new = stored_thread.rev == 0

      prepared_entries = EntryNormalizer.normalize_many(entries, base_seq, now)
      all_entries = stored_thread.entries ++ prepared_entries
      new_rev = stored_thread.rev + length(prepared_entries)

      thread_metadata =
        if is_new do
          Keyword.get(opts, :metadata, stored_thread.metadata)
        else
          stored_thread.metadata
        end

      created_at = if is_new, do: now, else: stored_thread.created_at

      updated_thread = %{
        rev: new_rev,
        created_at: created_at,
        updated_at: now,
        metadata: thread_metadata,
        entries: all_entries
      }

      binary = :erlang.term_to_binary(updated_thread)
      command = set_command(redis_key, binary, Keyword.get(opts, :ttl))

      with {:ok, _} <- command_fn.(command) do
        {:ok, reconstruct_thread(thread_id, updated_thread)}
      else
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp load_thread_or_new(command_fn, redis_key, now) do
    case command_fn.(["GET", redis_key]) do
      {:ok, nil} ->
        {:ok,
         %{
           rev: 0,
           created_at: now,
           updated_at: now,
           metadata: %{},
           entries: []
         }}

      {:ok, binary} ->
        decode_thread(binary)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected_rev, expected_rev), do: :ok
  defp validate_expected_rev(_expected_rev, _current_rev), do: {:error, :conflict}

  defp reconstruct_thread(thread_id, stored_thread) do
    entry_count = length(stored_thread.entries)

    %Thread{
      id: thread_id,
      rev: stored_thread.rev,
      entries: stored_thread.entries,
      created_at: stored_thread.created_at,
      updated_at: stored_thread.updated_at,
      metadata: stored_thread.metadata,
      stats: %{entry_count: entry_count}
    }
  end

  defp checkpoint_key(key, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)
    "#{prefix}:cp:#{hash}"
  end

  defp thread_key(thread_id, opts) do
    prefix = Keyword.get(opts, :prefix, @default_prefix)
    "#{prefix}:th:#{thread_id}"
  end

  defp set_command(redis_key, binary, nil), do: ["SET", redis_key, binary]
  defp set_command(redis_key, binary, ttl), do: ["SET", redis_key, binary, "PX", to_string(ttl)]

  defp decode_thread(binary) do
    with {:ok, stored_thread} <- safe_binary_to_term(binary),
         {:ok, validated_thread} <- validate_thread(stored_thread) do
      {:ok, validated_thread}
    end
  end

  defp validate_thread(%{
         rev: rev,
         created_at: created_at,
         updated_at: updated_at,
         metadata: metadata,
         entries: entries
       })
       when is_integer(rev) and rev >= 0 and is_integer(created_at) and is_integer(updated_at) and
              is_map(metadata) and is_list(entries) do
    cond do
      rev != length(entries) ->
        {:error, :invalid_term}

      not valid_entries?(entries) ->
        {:error, :invalid_term}

      true ->
        {:ok,
         %{
           rev: rev,
           created_at: created_at,
           updated_at: updated_at,
           metadata: metadata,
           entries: entries
         }}
    end
  end

  defp validate_thread(_), do: {:error, :invalid_term}

  defp valid_entries?(entries) do
    entries
    |> Enum.with_index()
    |> Enum.all?(fn {entry, expected_seq} ->
      valid_entry?(entry) and entry.seq == expected_seq
    end)
  end

  defp valid_entry?(%Entry{
         id: id,
         seq: seq,
         at: at,
         kind: kind,
         payload: payload,
         refs: refs
       })
       when is_binary(id) and is_integer(seq) and seq >= 0 and is_integer(at) and is_atom(kind) and
              is_map(payload) and is_map(refs),
       do: true

  defp valid_entry?(%{
         id: id,
         seq: seq,
         at: at,
         kind: kind,
         payload: payload,
         refs: refs
       })
       when is_binary(id) and is_integer(seq) and seq >= 0 and is_integer(at) and is_atom(kind) and
              is_map(payload) and is_map(refs),
       do: true

  defp valid_entry?(_), do: false

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
