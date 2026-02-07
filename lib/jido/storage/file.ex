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
          └── {thread_id}/
              ├── meta.term          # {rev, created_at, updated_at, metadata}
              └── entries.log        # Length-prefixed binary frames

  ## Concurrency

  Uses `:global.trans/3` for thread-level locking to ensure safe concurrent access.
  """

  @behaviour Jido.Storage

  alias Jido.Thread
  alias Jido.Thread.Entry

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
        {:ok, :erlang.binary_to_term(binary, [:safe])}

      {:error, :enoent} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_term}
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
    thread_dir = thread_path(path, thread_id)
    meta_file = Path.join(thread_dir, "meta.term")
    entries_file = Path.join(thread_dir, "entries.log")

    with {:ok, meta_binary} <- File.read(meta_file),
         {:ok, entries_binary} <- File.read(entries_file) do
      {rev, created_at, updated_at, metadata} = :erlang.binary_to_term(meta_binary, [:safe])
      entries = decode_entries(entries_binary)

      thread = %Thread{
        id: thread_id,
        rev: rev,
        entries: entries,
        created_at: created_at,
        updated_at: updated_at,
        metadata: metadata,
        stats: %{entry_count: length(entries)}
      }

      {:ok, thread}
    else
      {:error, :enoent} -> :not_found
      {:error, reason} -> {:error, reason}
    end
  rescue
    ArgumentError -> {:error, :invalid_term}
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

    with_thread_lock(thread_id, fn ->
      do_append_thread(path, thread_id, entries, expected_rev)
    end)
  end

  @doc """
  Delete a thread and all its data.

  Removes the entire thread directory.
  """
  @impl true
  @spec delete_thread(String.t(), opts()) :: :ok | {:error, term()}
  def delete_thread(thread_id, opts) do
    path = Keyword.fetch!(opts, :path)
    thread_dir = thread_path(path, thread_id)

    case File.rm_rf(thread_dir) do
      {:ok, _} -> :ok
      {:error, reason, _} -> {:error, reason}
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp do_append_thread(path, thread_id, entries, expected_rev) do
    thread_dir = thread_path(path, thread_id)
    meta_file = Path.join(thread_dir, "meta.term")
    entries_file = Path.join(thread_dir, "entries.log")

    {current_rev, current_entries, created_at, metadata} =
      load_thread_or_new(meta_file, entries_file)

    with :ok <- validate_expected_rev(expected_rev, current_rev),
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
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_thread_or_new(meta_file, entries_file) do
    case load_existing_thread(meta_file, entries_file) do
      {:ok, rev, existing_entries, created, meta} ->
        {rev, existing_entries, created, meta}

      :not_found ->
        now = System.system_time(:millisecond)
        {0, [], now, %{}}
    end
  end

  defp validate_expected_rev(nil, _current_rev), do: :ok
  defp validate_expected_rev(expected_rev, expected_rev), do: :ok
  defp validate_expected_rev(_expected_rev, _current_rev), do: {:error, :conflict}

  defp build_prepared_entries(entries, current_entries) do
    now = System.system_time(:millisecond)
    base_seq = length(current_entries)

    prepared_entries =
      entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        %Entry{
          id: entry.id || generate_entry_id(),
          seq: base_seq + idx,
          at: entry.at || now,
          kind: entry.kind,
          payload: entry.payload || %{},
          refs: entry.refs || %{}
        }
      end)

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
         {:ok, entries_binary} <- File.read(entries_file) do
      {rev, created_at, _updated_at, metadata} = :erlang.binary_to_term(meta_binary, [:safe])
      entries = decode_entries(entries_binary)
      {:ok, rev, entries, created_at, metadata}
    else
      {:error, :enoent} -> :not_found
      {:error, _reason} -> :not_found
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

  defp decode_entries(<<>>), do: []

  defp decode_entries(<<size::unsigned-32, rest::binary>>) do
    <<term_binary::binary-size(size), remaining::binary>> = rest
    entry = :erlang.binary_to_term(term_binary, [:safe])
    [entry | decode_entries(remaining)]
  end

  defp checkpoint_path(base_path, key) do
    hash = :crypto.hash(:sha256, :erlang.term_to_binary(key)) |> Base.url_encode64(padding: false)
    Path.join([base_path, "checkpoints", "#{hash}.term"])
  end

  defp thread_path(base_path, thread_id) do
    Path.join([base_path, "threads", thread_id])
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

  defp with_thread_lock(thread_id, fun) do
    lock_id = {:jido_thread_lock, thread_id}

    :global.trans(lock_id, fn ->
      fun.()
    end)
  end

  defp generate_entry_id do
    "entry_" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end
end
