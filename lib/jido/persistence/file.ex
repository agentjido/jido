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

  @behaviour Jido.Persistence.Adapter

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    case File.read(record_path(Keyword.fetch!(opts, :path), key)) do
      {:ok, value} -> {:ok, value}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    with_lock(key, opts, fn file_path -> write_record(file_path, value) end)
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    with_lock(key, opts, fn file_path ->
      case {File.read(file_path), expected} do
        {{:error, :enoent}, :not_found} -> write_record(file_path, value)
        {{:ok, current}, current} -> write_record(file_path, value)
        {{:ok, _current}, _expected} -> {:error, :conflict}
        {{:error, :enoent}, _expected} -> {:error, :conflict}
        {{:error, reason}, _expected} -> {:error, reason}
      end
    end)
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    with_lock(key, opts, fn file_path ->
      case File.rm(file_path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp with_lock(key, opts, fun) do
    file_path = opts |> Keyword.fetch!(:path) |> record_path(key) |> Path.expand()
    :global.trans({{__MODULE__, file_path}, self()}, fn -> fun.(file_path) end, [node()])
  end

  defp write_record(file_path, value) do
    temporary_path = file_path <> ".#{System.unique_integer([:positive, :monotonic])}.tmp"

    with :ok <- File.mkdir_p(Path.dirname(file_path)),
         :ok <- File.write(temporary_path, value),
         :ok <- File.rename(temporary_path, file_path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary_path)
        {:error, reason}
    end
  end

  defp record_path(base_path, key) do
    hash = :crypto.hash(:sha256, key) |> Base.url_encode64(padding: false)
    Path.join([base_path, "records", "#{hash}.bin"])
  end
end
