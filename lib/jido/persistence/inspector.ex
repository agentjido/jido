defmodule Jido.Persistence.Inspector do
  @moduledoc """
  Read-only helpers for persistence inspection and JSONL export.

  Exact inspection returns a metadata and shape projection unless `full: true`
  is set. JSONL export redacts Agent state unless `include_state: true` is set.
  Execution data stays shape-only in normal exports.
  """

  alias Jido.Persistence.{Config, Store}

  @redacted "[REDACTED]"

  @spec read(Config.t(), binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def read(%Config{} = config, key, opts \\ []) when is_binary(key) do
    with {:ok, bytes, _condition} <- Store.read(config.store, key),
         {:ok, value} <- decode(config, key, bytes, opts) do
      {:ok, project(key, value, Keyword.put(opts, :inspection_mode, :read))}
    end
  end

  @spec export_jsonl(Config.t(), binary(), term(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def export_jsonl(%Config{} = config, prefix, io, opts \\ []) when is_binary(prefix) do
    export_page(config, prefix, io, opts, nil, 0)
  end

  @spec json_line(binary(), term()) :: {:ok, binary()} | {:error, term()}
  def json_line(key, value) do
    with {:ok, encoded} <- Jido.Persistence.Codec.JSON.encode(value),
         {:ok, envelope} <- JSON.decode(encoded) do
      {:ok, JSON.encode!(%{"key" => key, "record" => envelope["value"]}) <> "\n"}
    end
  end

  @spec redact(term()) :: term()
  def redact(%{__struct__: module} = struct) do
    fields = struct |> Map.from_struct() |> redact()
    struct(module, fields)
  end

  def redact({:jido_execution_prepared, version, _value}),
    do: {:jido_execution_prepared, version, @redacted}

  def redact({:jido_fact_value, version, sequence, digest, :full, _value}),
    do: {:jido_fact_value, version, sequence, digest, :full, @redacted}

  def redact(map) when is_map(map) do
    Map.new(map, fn
      {key, _value} when key in [:state, "state"] -> {key, @redacted}
      {key, value} -> {key, redact(value)}
    end)
  end

  def redact(list) when is_list(list), do: Enum.map(list, &redact/1)
  def redact(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&redact/1) |> List.to_tuple()
  def redact(value), do: value

  defp export_page(config, prefix, io, opts, cursor, count) do
    limit = Keyword.get(opts, :limit, 100)

    with {:ok, entries, next_cursor} <- Store.scan(config.store, prefix, cursor: cursor, limit: limit),
         {:ok, written} <- write_entries(config, entries, io, opts) do
      if is_nil(next_cursor),
        do: {:ok, count + written},
        else: export_page(config, prefix, io, opts, next_cursor, count + written)
    end
  end

  defp write_entries(config, entries, io, opts) do
    Enum.reduce_while(entries, {:ok, 0}, fn {key, bytes}, {:ok, count} ->
      with {:ok, value} <- decode(config, key, bytes, opts),
           value <- project(key, value, Keyword.put(opts, :inspection_mode, :export)),
           {:ok, line} <- json_line(key, value),
           :ok <- IO.binwrite(io, line) do
        {:cont, {:ok, count + 1}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode(_config, "jido:namespace:v3:" <> _rest, bytes, _opts) when is_binary(bytes) do
    with {:ok, value} <- Jido.Persistence.Codec.JSON.decode(bytes, []),
         :ok <- validate_namespace_manifest(value) do
      {:ok, value}
    end
  end

  defp decode(config, "jido:agent:v3:" <> _rest = key, bytes, _opts) when is_binary(bytes) do
    with {:ok, value} <- Config.decode(config, bytes),
         :ok <- validate_agent_record(key, value) do
      {:ok, value}
    end
  end

  defp decode(config, "jido:execution:v3:" <> _rest = key, bytes, _opts) when is_binary(bytes) do
    with {:ok, value} <- Config.decode(config, bytes),
         :ok <- validate_execution_record(key, value) do
      {:ok, value}
    end
  end

  defp decode(config, "jido:wake:v3:" <> _rest, bytes, _opts) when is_binary(bytes) do
    with {:ok, value} <- Config.decode(config, bytes),
         :ok <- validate_wake_record(value) do
      {:ok, value}
    end
  end

  defp decode(_config, _key, _bytes, _opts), do: {:error, :unsupported_persistence_record}

  defp validate_namespace_manifest(%{
         format: 1,
         namespace: namespace,
         codec: %{id: id, version: codec_version},
         records: %{agent: 3, execution: 3, wake: 3},
         wake: %{bucket_ms: 60_000, shards: 64}
       })
       when is_binary(namespace) and is_binary(id) and is_integer(codec_version) and codec_version > 0,
       do: :ok

  defp validate_namespace_manifest(_value), do: {:error, :invalid_persistence_namespace_manifest}

  defp validate_agent_record(
         key,
         %{agent_module: module, namespace: namespace, agent_id: id, partition: partition} = value
       )
       when is_atom(module) and is_binary(namespace) and is_binary(id) do
    with {:ok, address} <- Jido.Agent.Address.new(namespace: namespace, id: id, partition: partition),
         true <- Jido.Persistence.agent_key(address) == key,
         :ok <- Jido.Persistence.Record.validate(value, address, module) do
      :ok
    else
      _ -> {:error, :invalid_persistence_record}
    end
  end

  defp validate_agent_record(_key, _value), do: {:error, :invalid_persistence_record}

  defp validate_execution_record(key, {:jido_execution_prepared, 3, _value}) do
    if String.ends_with?(key, ":prepared"), do: :ok, else: {:error, :invalid_execution_checkpoint}
  end

  defp validate_execution_record(key, {:jido_fact_index, 1, hashes}) when is_list(hashes) do
    if String.ends_with?(key, ":facts:index"), do: :ok, else: {:error, :invalid_execution_checkpoint}
  end

  defp validate_execution_record(
         key,
         {:jido_fact_value, 1, 0, digest, :full, _value}
       )
       when is_binary(digest) and byte_size(digest) == 32 do
    if String.contains?(key, ":facts:") and not String.ends_with?(key, ":facts:index"),
      do: :ok,
      else: {:error, :invalid_execution_checkpoint}
  end

  defp validate_execution_record(key, value) when is_integer(value) and value >= 0 do
    if String.contains?(key, ":batches:") or String.contains?(key, ":facts:"),
      do: {:error, :invalid_execution_checkpoint},
      else: :ok
  end

  defp validate_execution_record(key, [_ | _]) do
    if String.contains?(key, ":batches:"), do: :ok, else: {:error, :invalid_execution_checkpoint}
  end

  defp validate_execution_record(_key, _value), do: {:error, :invalid_execution_checkpoint}

  defp validate_wake_record(%{format: 3, buckets: buckets}) when is_map(buckets), do: :ok

  defp validate_wake_record(%{
         format: 3,
         bucket: bucket,
         shard: shard,
         generation: generation,
         entries: entries
       })
       when is_integer(bucket) and is_integer(shard) and shard >= 0 and shard < 64 and
              is_integer(generation) and generation > 0 and is_list(entries),
       do: :ok

  defp validate_wake_record(_value), do: {:error, :invalid_wake_record}

  defp project(_key, value, opts) when is_list(opts) do
    if Keyword.get(opts, :full, false) do
      value
    else
      project_redacted(value, opts)
    end
  end

  defp project_redacted({:jido_execution_prepared, version, value}, _opts) do
    %{kind: "execution_prepared", version: version, value: shape(value)}
  end

  defp project_redacted({:jido_fact_value, version, sequence, digest, :full, value}, _opts) do
    %{
      kind: "execution_fact",
      version: version,
      sequence: sequence,
      digest: Base.encode16(digest, case: :lower),
      value: shape(value)
    }
  end

  defp project_redacted(events, _opts) when is_list(events) do
    %{kind: "execution_batch", event_count: length(events), events: Enum.map(events, &shape/1)}
  end

  defp project_redacted(value, opts) do
    if Keyword.get(opts, :inspection_mode) == :export and
         Keyword.get(opts, :include_state, false),
       do: value,
       else: redact(value)
  end

  defp shape(%{__struct__: module} = struct) do
    %{
      kind: "struct",
      type: Atom.to_string(module),
      fields: struct |> Map.from_struct() |> Map.keys() |> Enum.map(&field_name/1) |> Enum.sort()
    }
  end

  defp shape(map) when is_map(map) do
    %{kind: "map", fields: map |> Map.keys() |> Enum.map(&field_name/1) |> Enum.sort()}
  end

  defp shape(tuple) when is_tuple(tuple), do: %{kind: "tuple", size: tuple_size(tuple)}
  defp shape(list) when is_list(list), do: %{kind: "list", size: length(list)}
  defp shape(value) when is_binary(value), do: %{kind: "binary", bytes: byte_size(value)}
  defp shape(value) when is_atom(value), do: %{kind: "atom"}
  defp shape(value) when is_integer(value), do: %{kind: "integer"}
  defp shape(value) when is_float(value), do: %{kind: "float"}
  defp shape(_value), do: %{kind: "other"}

  defp field_name(value) when is_atom(value), do: Atom.to_string(value)
  defp field_name(value) when is_binary(value), do: value
  defp field_name(_value), do: "[non-string-key]"
end
