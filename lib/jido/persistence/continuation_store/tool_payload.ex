defmodule Jido.Persistence.ContinuationStore.ToolPayload do
  @moduledoc false

  # Smaller values usually cost less to keep inline than to look up.
  @min_bytes 256
  @tag :jido_tool_payload_refs

  def new, do: {%{}, nil}

  def add(catalogue, slot, payloads), do: add_references(catalogue, payloads, fn _digest -> slot end)

  def add_shared(catalogue, payloads), do: add_references(catalogue, payloads, &{:shared, &1})

  def known?({known, _pattern}, bytes), do: Map.has_key?(known, bytes)

  def without_source({known, _pattern} = catalogue, source) do
    kept = Map.reject(known, fn {_bytes, {candidate, _digest}} -> candidate == source end)
    if map_size(kept) == map_size(known), do: catalogue, else: compile(kept)
  end

  defp add_references({known, _pattern} = catalogue, payloads, source) do
    added =
      Enum.reduce(payloads, known, fn {digest, bytes}, acc ->
        Map.put_new(acc, bytes, {source.(digest), digest})
      end)

    if map_size(added) == map_size(known),
      do: catalogue,
      else: compile(added)
  end

  defp compile(known) when map_size(known) == 0, do: new()
  defp compile(known), do: {known, :binary.compile_pattern(Map.keys(known))}

  def payloads(outcome, acc \\ %{}), do: collect(outcome, acc)

  defp collect(bytes, acc) when is_binary(bytes) and byte_size(bytes) >= @min_bytes,
    do: Map.put(acc, digest(bytes), bytes)

  defp collect(map, acc) when is_map(map),
    do: Enum.reduce(:maps.values(map), acc, &collect/2)

  defp collect([head | tail], acc), do: collect(tail, collect(head, acc))
  defp collect(tuple, acc) when is_tuple(tuple), do: collect(Tuple.to_list(tuple), acc)
  defp collect(_other, acc), do: acc

  def digest(bytes), do: :crypto.hash(:sha256, bytes)

  def pack(bytes, {_refs, nil}), do: bytes

  def pack(bytes, {refs, pattern}) do
    case :binary.matches(bytes, pattern) do
      [] -> bytes
      matches -> {@tag, 1, segments(bytes, refs, matches)}
    end
  end

  defp segments(bytes, refs, matches) do
    {reversed, offset} =
      Enum.reduce(matches, {[], 0}, fn {start, length}, {acc, offset} ->
        matched = :binary.part(bytes, start, length)
        reference = Map.fetch!(refs, matched)
        prefix = :binary.part(bytes, offset, start - offset)
        {[reference, prefix | acc], start + length}
      end)

    Enum.reverse(reversed, [:binary.part(bytes, offset, byte_size(bytes) - offset)])
  end

  def unpack(bytes, _load) when is_binary(bytes), do: {:ok, bytes}

  def unpack({@tag, 1, segments}, load) when is_list(segments) do
    if List.improper?(segments),
      do: {:error, :invalid_execution_checkpoint},
      else: restore_segments(segments, load)
  end

  def unpack(_invalid, _load), do: {:error, :invalid_execution_checkpoint}

  defp restore_segments(segments, load) do
    Enum.reduce_while(segments, {[], %{}}, fn
      bytes, {parts, cache} when is_binary(bytes) ->
        {:cont, {[bytes | parts], cache}}

      {slot, digest}, {parts, cache} when is_binary(digest) and byte_size(digest) == 32 ->
        with {:ok, payloads, cache} <- fetch_slot(cache, slot, load),
             {:ok, bytes} <- Map.fetch(payloads, digest) do
          {:cont, {[bytes | parts], cache}}
        else
          _unavailable -> {:halt, {:error, :invalid_execution_checkpoint}}
        end

      _invalid, _acc ->
        {:halt, {:error, :invalid_execution_checkpoint}}
    end)
    |> case do
      {parts, _cache} when is_list(parts) -> {:ok, IO.iodata_to_binary(Enum.reverse(parts))}
      error -> error
    end
  end

  defp fetch_slot(cache, slot, load) do
    case Map.fetch(cache, slot) do
      {:ok, payloads} ->
        {:ok, payloads, cache}

      :error ->
        with {:ok, payloads} <- load.(slot), do: {:ok, payloads, Map.put(cache, slot, payloads)}
    end
  end
end
