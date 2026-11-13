defmodule Jido.Persistence.File do
  @moduledoc """
  File persistence adapter for binary keys and values.

  The required `:path` option selects the base directory. Writes use a
  temporary file and an atomic rename. Writes and deletes for a key share a
  lock within the local BEAM instance.

  One BEAM instance must own the directory. Separate OS processes or BEAM
  instances must not write to it at the same time. All callers must use the
  same path, without alternate symbolic links. Use Redis for shared storage
  across BEAM instances.
  """

  @behaviour Jido.Persistence.Store
  @scan_node_budget 4_096

  @impl true
  def validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) -> {:error, "options must be a keyword list"}
      Keyword.keys(opts) -- [:path] != [] -> {:error, "supports only the :path option"}
      Keyword.keys(opts) -- Enum.uniq(Keyword.keys(opts)) != [] -> {:error, "options must be unique"}
      not is_binary(Keyword.get(opts, :path)) -> {:error, ":path must be a non-empty string"}
      Keyword.get(opts, :path) == "" -> {:error, ":path must be a non-empty string"}
      true -> :ok
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)

    case File.read(record_path(Keyword.fetch!(opts, :path), key)) do
      {:ok, value} -> {:ok, value}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    validate_options!(opts)
    with_lock(key, opts, fn base_path, file_path -> write_record(base_path, file_path, key, value) end)
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    validate_options!(opts)

    with_lock(key, opts, fn base_path, file_path ->
      case {File.read(file_path), expected} do
        {{:error, :enoent}, :not_found} -> write_record(base_path, file_path, key, value)
        {{:ok, current}, current} -> write_record(base_path, file_path, key, value)
        {{:ok, _current}, _expected} -> {:error, :conflict}
        {{:error, :enoent}, _expected} -> {:error, :conflict}
        {{:error, reason}, _expected} -> {:error, reason}
      end
    end)
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)

    with_lock(key, opts, fn base_path, file_path ->
      with :ok <- remove_index_marker(base_path, key),
           :ok <- remove_file(file_path),
           :ok <- remove_file(key_path(file_path)) do
        :ok
      end
    end)
  end

  @impl true
  def scan(prefix, cursor, limit, opts)
      when is_binary(prefix) and (is_nil(cursor) or is_binary(cursor)) and is_integer(limit) and
             limit > 0 and is_list(opts) do
    validate_options!(opts)
    base_path = Keyword.fetch!(opts, :path)

    with {:ok, pending} <- scan_pending(base_path, prefix, cursor) do
      read_page(base_path, pending, prefix, limit, [], @scan_node_budget)
    end
  end

  defp with_lock(key, opts, fun) do
    base_path = opts |> Keyword.fetch!(:path) |> Path.expand()
    file_path = record_path(base_path, key)
    :global.trans({{__MODULE__, file_path}, self()}, fn -> fun.(base_path, file_path) end, [node()])
  end

  defp validate_options!(opts) do
    case validate_options(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "Jido.Persistence.File #{reason}"
    end
  end

  defp write_record(base_path, file_path, key, value) do
    with :ok <- File.mkdir_p(Path.dirname(file_path)),
         :ok <- ensure_key_file(key_path(file_path), key),
         :ok <- write_file(file_path, value),
         :ok <- ensure_index_marker(base_path, key) do
      :ok
    end
  end

  defp ensure_index_marker(base_path, key) do
    with_index_lock(base_path, fn ->
      path = index_marker_path(base_path, key)

      with :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- ensure_key_file(path, key) do
        :ok
      end
    end)
  end

  defp remove_index_marker(base_path, key) do
    with_index_lock(base_path, fn ->
      path = index_marker_path(base_path, key)

      with :ok <- remove_file(path) do
        prune_index_path(Path.dirname(path), index_root(base_path))
      end
    end)
  end

  defp with_index_lock(base_path, fun) do
    :global.trans({{__MODULE__, :scan_index, base_path}, self()}, fun, [node()])
  end

  defp prune_index_path(path, root) when path == root, do: :ok

  defp prune_index_path(path, root) do
    case File.rmdir(path) do
      :ok -> prune_index_path(Path.dirname(path), root)
      {:error, :enoent} -> prune_index_path(Path.dirname(path), root)
      {:error, :eexist} -> :ok
      {:error, :enotempty} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_key_file(path, key) do
    case File.read(path) do
      {:ok, ^key} -> :ok
      {:ok, _other} -> {:error, {:rejected, :key_hash_collision}}
      {:error, :enoent} -> write_file(path, key)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_file(path, value) do
    temporary_path = path <> ".#{System.unique_integer([:positive, :monotonic])}.tmp"

    with :ok <- File.write(temporary_path, value),
         :ok <- File.rename(temporary_path, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary_path)
        {:error, reason}
    end
  end

  defp record_path(base_path, key) do
    hash = key |> key_hash() |> Base.url_encode64(padding: false)
    Path.join([base_path, "records", "#{hash}.bin"])
  end

  defp key_path(file_path), do: Path.rootname(file_path, ".bin") <> ".key"

  defp index_root(base_path), do: Path.join(base_path, "scan_index")

  defp index_node_path(base_path, hash_prefix) do
    hash_prefix
    |> :binary.bin_to_list()
    |> Enum.reduce(index_root(base_path), fn byte, path ->
      Path.join(path, Base.encode16(<<byte>>, case: :lower))
    end)
  end

  defp index_marker_path(base_path, key),
    do: Path.join(index_node_path(base_path, key_hash(key)), ".key")

  defp index_marker_for_hash(base_path, hash_prefix),
    do: Path.join(index_node_path(base_path, hash_prefix), ".key")

  defp key_hash(key), do: :crypto.hash(:sha256, key)

  defp remove_file(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp scan_pending(base_path, _prefix, nil) do
    if File.dir?(index_root(base_path)), do: {:ok, [<<>>]}, else: {:ok, []}
  end

  defp scan_pending(_base_path, prefix, cursor) when byte_size(cursor) <= 1_000_000 do
    with {:ok, %{"version" => 1, "prefix" => encoded_prefix, "pending" => encoded_pending} = decoded} <-
           JSON.decode(cursor),
         true <- map_size(decoded) == 3 and is_list(encoded_pending),
         {:ok, ^prefix} <- Base.decode64(encoded_prefix),
         true <- length(encoded_pending) <= 65_536,
         {:ok, pending} <- decode_pending(encoded_pending) do
      {:ok, pending}
    else
      _ -> {:error, :invalid_scan_cursor}
    end
  end

  defp scan_pending(_base_path, _prefix, _cursor), do: {:error, :invalid_scan_cursor}

  defp decode_pending(encoded) do
    Enum.reduce_while(encoded, {:ok, []}, fn value, {:ok, pending} ->
      case Base.decode64(value) do
        {:ok, hash_prefix} when byte_size(hash_prefix) <= 32 ->
          {:cont, {:ok, [hash_prefix | pending]}}

        _ ->
          {:halt, {:error, :invalid_scan_cursor}}
      end
    end)
    |> case do
      {:ok, pending} -> {:ok, Enum.reverse(pending)}
      error -> error
    end
  end

  defp encode_cursor(prefix, pending) do
    cursor =
      JSON.encode!(%{
        "version" => 1,
        "prefix" => Base.encode64(prefix),
        "pending" => Enum.map(pending, &Base.encode64/1)
      })

    if byte_size(cursor) <= 1_000_000, do: {:ok, cursor}, else: {:error, :scan_cursor_too_large}
  end

  defp read_page(_base_path, [], _prefix, _remaining, entries, _budget),
    do: {:ok, Enum.reverse(entries), nil}

  defp read_page(_base_path, pending, prefix, _remaining, entries, 0) do
    with {:ok, cursor} <- next_cursor(prefix, pending) do
      {:ok, Enum.reverse(entries), cursor}
    end
  end

  defp read_page(base_path, [hash_prefix | rest], prefix, remaining, entries, budget) do
    with {:ok, children} <- index_children(base_path, hash_prefix) do
      pending = children ++ rest

      case File.read(index_marker_for_hash(base_path, hash_prefix)) do
        {:ok, key} when is_binary(key) ->
          cond do
            key_hash(key) != hash_prefix ->
              {:error, :invalid_scan_index}

            binary_prefix?(key, prefix) ->
              with {:ok, value} <- File.read(record_path(base_path, key)) do
                entries = [{key, value} | entries]

                if remaining == 1 do
                  with {:ok, next_cursor} <- next_cursor(prefix, pending) do
                    {:ok, Enum.reverse(entries), next_cursor}
                  end
                else
                  read_page(base_path, pending, prefix, remaining - 1, entries, budget - 1)
                end
              end

            true ->
              read_page(base_path, pending, prefix, remaining, entries, budget - 1)
          end

        {:error, :enoent} ->
          read_page(base_path, pending, prefix, remaining, entries, budget - 1)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp next_cursor(_prefix, []), do: {:ok, nil}
  defp next_cursor(prefix, pending), do: encode_cursor(prefix, pending)

  defp index_children(base_path, hash_prefix) do
    case File.ls(index_node_path(base_path, hash_prefix)) do
      {:ok, names} ->
        children =
          names
          |> Enum.reduce([], fn name, found ->
            case Base.decode16(name, case: :mixed) do
              {:ok, <<byte>>} when byte_size(hash_prefix) < 32 ->
                [hash_prefix <> <<byte>> | found]

              _ ->
                found
            end
          end)
          |> Enum.sort()

        {:ok, children}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp binary_prefix?(value, prefix) do
    prefix_size = byte_size(prefix)
    byte_size(value) >= prefix_size and binary_part(value, 0, prefix_size) == prefix
  end
end
