defmodule Jido.Storage.File do
  @moduledoc """
  File-based storage adapter for Jido.

  Provides persistent storage for agent checkpoints and thread journals using
  a directory-based layout. Suitable for simple production deployments.

  ## Usage

      defmodule MyApp.Jido do
        use Jido,
          otp_app: :my_app,
          storage: {Jido.Storage.File, path: "priv/jido/storage"}
      end

  ## Options

  - `:path` - Base directory path (required). Created if it doesn't exist.

  ## Directory Layout

      base_path/
      ├── checkpoints/
      │   └── {key_hash}.term       # Serialized checkpoint
      └── threads/
          └── {thread_id}/          # thread_id must be a single path segment
              ├── meta.term          # {rev, created_at, updated_at, metadata}
              └── entries.log        # Length-prefixed binary frames

  ## Concurrency

  Uses `:global.trans/2` for thread-level locking to ensure safe concurrent access.
  """

  @behaviour Jido.Storage

  alias Jido.Thread
  alias Jido.Thread.Entry
  alias Jido.Thread.EntryNormalizer

  @type key :: term()
  @type opts :: keyword()

  # =============================================================================
  # Checkpoint Operations
  # =============================================================================

  @doc """
  Retrieve a checkpoint by key.

  Returns `{:ok, data}` if found, `:not_found` if the file doesn't exist,
  or `{:error, reason}` on failure.
  """
  @impl true
  @spec get_checkpoint(key(), opts()) :: {:ok, term()} | :not_found | {:error, term()}
  def get_checkpoint(key, opts) do
    path = Keyword.fetch!(opts, :path)
    file_path = checkpoint_path(path, key)

    case File.read(file_path) do
      {:ok, binary} ->
        safe_binary_to_term(binary, :invalid_term)

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Store a checkpoint with atomic write semantics.

  Writes to a temporary file first, then renames for atomicity.
  """
  @impl true
  @spec put_checkpoint(key(), term(), opts()) :: :ok | {:error, term()}
  def put_checkpoint(key, data, opts) do
    path = Keyword.fetch!(opts, :path)
    ensure_checkpoints_dir(path)
    file_path = checkpoint_path(path, key)
    tmp_path = file_path <> ".tmp"
    binary = :erlang.term_to_binary(data)

    with :ok <- File.write(tmp_path, binary),
         :ok <- File.rename(tmp_path, file_path) do
      :ok
    else
      {:error, reason} ->
        File.rm(tmp_path)
        {:error, reason}
    end
  end

  @doc """
  Delete a checkpoint.

  Returns `:ok` even if the file doesn't exist.
  """
  @impl true
  @spec delete_checkpoint(key(), opts()) :: :ok | {:error, term()}
  def delete_checkpoint(key, opts) do
    path = Keyword.fetch!(opts, :path)
    file_path = checkpoint_path(path, key)

    case File.rm(file_path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # =============================================================================
  # Thread Operations
  # =============================================================================

  @doc """
  Load a thread from disk.

  Reads the meta file and entries log, reconstructing a `%Jido.Thread{}`.
  Returns `:not_found` if the thread directory doesn't exist.
  """
  @impl true
  @spec load_thread(String.t(), opts()) :: {:ok, Thread.t()} | :not_found | {:error, term()}
  def load_thread(thread_id, opts) do
    path = Keyword.fetch!(opts, :path)

    with {:ok, thread_dir} <- thread_path(path, thread_id),
         meta_file = Path.join(thread_dir, "meta.term"),
         entries_file = Path.join(thread_dir, "entries.log"),
         {:ok, meta_binary} <- File.read(meta_file),
         {:ok, entries_binary} <- File.read(entries_file),
         {:ok, {rev, created_at, updated_at, metadata}} <- decode_meta(meta_binary),
         {:ok, entries} <- decode_entries(entries_binary) do
      reconstruct_thread(thread_id, rev, created_at, updated_at, metadata, entries)
    else
      {:error, :enoent} -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Append entries to a thread with optimistic concurrency.

  Options:
  - `:expected_rev` - Expected current revision. Fails with `{:error, :conflict}`
    if the current revision doesn't match.

  Uses a global lock to ensure safe concurrent access.
  """
  @impl true
  @spec append_thread(String.t(), [Entry.t()], opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def append_thread(thread_id, entries, opts) do
    path = Keyword.fetch!(opts, :path)
    expected_rev = Keyword.get(opts, :expected_rev)

    with {:ok, thread_dir} <- thread_path(path, thread_id) do
      with_thread_lock(path, thread_id, fn ->
        do_append_thread(thread_id, thread_dir, entries, expected_rev)
      end)
    end
  end

  @doc """
  Delete a thread and all its data.

  Removes the entire thread directory.
  """
  @impl true
  @spec delete_thread(String.t(), opts()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    path = Keyword.fetch!(opts, :path)

    with {:ok, thread_dir} <- thread_path(path, thread_id) do
      case File.rm_rf(thread_dir) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, reason}
      end
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp do_append_thread(thread_id, thread_dir, entries, expected_rev) do
    meta_file = Path.join(thread_dir, "meta.term")
    entries_file = Path.join(thread_dir, "entries.log")

    with {:ok, current_rev, current_entries, created_at, metadata} <-
           load_thread_or_new(meta_file, entries_file),
         :ok <- validate_expected_rev(expected_rev, current_rev),
         :ok <- ensure_thread_dir(thread_dir),
         {:ok, prepared_entries, now} <- build_prepared_entries(entries, current_entries),
         :ok <- append_to_file(entries_file, encode_entries(prepared_entries)),
         {:ok, thread} <-
           persist_thread_meta(
             meta_file,
             thread_id,
             current_rev,
             current_entries,
             prepared_entries,
             created_at,
             metadata,
             now
           ) do
      {:ok, thread}
    end
  end

  defp load_thread_or_new(meta_file, entries_file) do
    case load_existing_thread(meta_file, entries_file) do
      {:ok, rev, existing_entries, created, meta} ->
        {:ok, rev, existing_entries, created, meta}

      :not_found ->
        now = System.system_time(:millisecond)
        {:ok, 0, [], now, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected_rev, expected_rev), do: :ok
  defp validate_expected_rev(_expected_rev, _current_rev), do: {:error, :conflict}

  defp build_prepared_entries(entries, current_entries) do
    now = System.system_time(:millisecond)
    base_seq = length(current_entries)

    prepared_entries = EntryNormalizer.normalize_many(entries, base_seq, now)

    {:ok, prepared_entries, now}
  end

  defp persist_thread_meta(
         meta_file,
         thread_id,
         current_rev,
         current_entries,
         prepared_entries,
         created_at,
         metadata,
         now
       ) do
    all_entries = current_entries ++ prepared_entries
    new_rev = current_rev + length(prepared_entries)

    meta = {new_rev, created_at, now, metadata}
    meta_binary = :erlang.term_to_binary(meta)
    tmp_meta = meta_file <> ".tmp"

    with :ok <- File.write(tmp_meta, meta_binary),
         :ok <- File.rename(tmp_meta, meta_file) do
      thread = %Thread{
        id: thread_id,
        rev: new_rev,
        entries: all_entries,
        created_at: created_at,
        updated_at: now,
        metadata: metadata,
        stats: %{entry_count: length(all_entries)}
      }

      {:ok, thread}
    else
      {:error, reason} ->
        File.rm(tmp_meta)
        {:error, reason}
    end
  end

  defp load_existing_thread(meta_file, entries_file) do
    with {:ok, meta_binary} <- File.read(meta_file),
         {:ok, entries_binary} <- File.read(entries_file),
         {:ok, {rev, created_at, _updated_at, metadata}} <- decode_meta(meta_binary),
         {:ok, entries} <- decode_entries(entries_binary) do
      with :ok <- validate_thread_rev(rev, entries) do
        {:ok, rev, entries, created_at, metadata}
      end
    else
      {:error, :enoent} -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  defp append_to_file(file_path, binary) do
    case File.open(file_path, [:append, :binary], fn file ->
           IO.binwrite(file, binary)
         end) do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  # Binary framing: <<size::unsigned-32, term_binary::binary>> for each entry
  defp encode_entries(entries) do
    Enum.reduce(entries, <<>>, fn entry, acc ->
      term_binary = :erlang.term_to_binary(entry)
      size = byte_size(term_binary)
      acc <> <<size::unsigned-32, term_binary::binary>>
    end)
  end

  defp decode_entries(binary), do: decode_entries(binary, [])

  defp decode_entries(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_entries(<<size::unsigned-32, rest::binary>>, acc) do
    with {:ok, term_binary, remaining} <- decode_frame(rest, size),
         {:ok, entry} <- decode_entry(term_binary) do
      decode_entries(remaining, [entry | acc])
    end
  end

  defp decode_entries(_malformed, _acc), do: {:error, :invalid_entries_log}

  defp decode_frame(rest, size) when byte_size(rest) >= size do
    <<term_binary::binary-size(^size), remaining::binary>> = rest
    {:ok, term_binary, remaining}
  end

  defp decode_frame(_rest, _size), do: {:error, :invalid_entries_log}

  defp decode_entry(term_binary) do
    with {:ok, term} <- safe_binary_to_term(term_binary, :invalid_entries_log),
         {:ok, entry} <- validate_entry(term) do
      {:ok, entry}
    end
  end

  defp decode_meta(binary) do
    with {:ok, term} <- safe_binary_to_term(binary, :invalid_term),
         {:ok, meta} <- validate_meta(term) do
      {:ok, meta}
    end
  end

  defp safe_binary_to_term(binary, error_reason) do
    {:ok, :erlang.binary_to_term(binary, [:safe])}
  rescue
    ArgumentError ->
      {:error, error_reason}
  end

  defp validate_meta({rev, created_at, updated_at, metadata} = meta)
       when is_integer(rev) and rev >= 0 and is_integer(created_at) and
              is_integer(updated_at) and is_map(metadata) do
    {:ok, meta}
  end

  defp validate_meta(_), do: {:error, :invalid_term}

  defp validate_entry(%Entry{} = entry) do
    case entry do
      %Entry{id: id, seq: seq, at: at, kind: kind, payload: payload, refs: refs}
      when is_binary(id) and is_integer(seq) and seq >= 0 and is_integer(at) and
             is_atom(kind) and is_map(payload) and is_map(refs) ->
        {:ok, entry}

      _ ->
        {:error, :invalid_entries_log}
    end
  end

  defp validate_entry(%{id: id, seq: seq, at: at, kind: kind, payload: payload, refs: refs})
       when is_binary(id) and is_integer(seq) and seq >= 0 and is_integer(at) and
              is_atom(kind) and is_map(payload) and is_map(refs) do
    {:ok, %Entry{id: id, seq: seq, at: at, kind: kind, payload: payload, refs: refs}}
  end

  defp validate_entry(_), do: {:error, :invalid_entries_log}

  defp validate_thread_rev(rev, entries) do
    if rev == length(entries), do: :ok, else: {:error, :invalid_term}
  end

  defp reconstruct_thread(thread_id, rev, created_at, updated_at, metadata, entries) do
    with :ok <- validate_thread_rev(rev, entries) do
      {:ok,
       %Thread{
         id: thread_id,
         rev: rev,
         entries: entries,
         created_at: created_at,
         updated_at: updated_at,
         metadata: metadata,
         stats: %{entry_count: length(entries)}
       }}
    end
  end

  defp checkpoint_path(base_path, key) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)
    Path.join([base_path, "checkpoints", "#{hash}.term"])
  end

  defp thread_path(base_path, thread_id) when is_binary(thread_id) and byte_size(thread_id) > 0 do
    cond do
      String.contains?(thread_id, <<0>>) ->
        {:error, :invalid_thread_id}

      Path.type(thread_id) == :absolute ->
        {:error, :invalid_thread_id}

      unsafe_thread_segment?(thread_id) ->
        {:error, :invalid_thread_id}

      true ->
        threads_root = threads_root(base_path)
        candidate = Path.expand(Path.join(threads_root, thread_id))

        if inside_path?(candidate, threads_root) do
          {:ok, candidate}
        else
          {:error, :invalid_thread_id}
        end
    end
  end

  defp thread_path(_base_path, _thread_id), do: {:error, :invalid_thread_id}

  defp unsafe_thread_segment?(thread_id) do
    thread_id in [".", ".."] or String.contains?(thread_id, ["/", "\\"])
  end

  defp threads_root(base_path), do: Path.expand(Path.join(base_path, "threads"))

  defp inside_path?(candidate, root) do
    root_parts = Path.split(root)
    candidate_parts = Path.split(candidate)

    length(candidate_parts) > length(root_parts) and
      Enum.take(candidate_parts, length(root_parts)) == root_parts
  end

  defp ensure_checkpoints_dir(base_path) do
    File.mkdir_p!(Path.join(base_path, "checkpoints"))
  end

  defp ensure_thread_dir(thread_dir) do
    File.mkdir_p!(thread_dir)

    # Ensure entries.log exists
    entries_file = Path.join(thread_dir, "entries.log")

    unless File.exists?(entries_file) do
      File.write!(entries_file, <<>>)
    end

    :ok
  end

  defp with_thread_lock(base_path, thread_id, fun) do
    lock_key = {:jido_thread_lock, Path.expand(base_path), thread_id}
    lock_id = {lock_key, self()}

    :global.trans(lock_id, fn ->
      fun.()
    end)
  end
end
