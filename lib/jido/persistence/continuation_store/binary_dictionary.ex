defmodule Jido.Persistence.ContinuationStore.BinaryDictionary do
  @moduledoc false

  alias Jido.Persistence.Codec.Term
  alias Runic.Identity

  @tag :jido_execution_dictionary

  def identity_patterns(value) do
    value
    |> collect_identities(MapSet.new())
    |> Enum.map(fn identity ->
      <<131, bytes::binary>> = :erlang.term_to_binary(identity, [:deterministic])
      bytes
    end)
  end

  def encode(bytes, []), do: {:ok, bytes}

  def encode(bytes, patterns) do
    matches =
      for {offset, length} <- :binary.matches(bytes, patterns),
          do: {offset, :binary.part(bytes, offset, length)}

    counts = Enum.frequencies_by(matches, &elem(&1, 1))
    repeats = Enum.filter(matches, fn {_offset, value} -> Map.fetch!(counts, value) > 1 end)

    case repeats do
      [] ->
        {:ok, bytes}

      [_ | _] ->
        {entries, parts} = dictionary(bytes, repeats)

        with {:ok, packed} <- Term.encode({@tag, 1, entries, parts}) do
          if byte_size(packed) < byte_size(bytes), do: {:ok, packed}, else: {:ok, bytes}
        end
    end
  end

  def unpack({@tag, 1, entries, parts}) when is_tuple(entries) and is_list(parts) do
    if List.improper?(parts) or not Enum.all?(Tuple.to_list(entries), &is_binary/1) do
      {:error, :invalid_execution_checkpoint}
    else
      parts
      |> Enum.reduce_while([], fn
        bytes, reversed when is_binary(bytes) ->
          {:cont, [bytes | reversed]}

        index, reversed when is_integer(index) and index >= 0 and index < tuple_size(entries) ->
          {:cont, [elem(entries, index) | reversed]}

        _invalid, _reversed ->
          {:halt, {:error, :invalid_execution_checkpoint}}
      end)
      |> case do
        {:error, _reason} = error -> error
        reversed -> {:ok, reversed |> Enum.reverse() |> IO.iodata_to_binary()}
      end
    end
  end

  def unpack(_record), do: {:error, :invalid_execution_checkpoint}

  defp dictionary(bytes, occurrences) do
    {indexes, reversed, offset} =
      Enum.reduce(occurrences, {%{}, [], 0}, fn {start, value}, {indexes, reversed, offset} ->
        index = Map.get(indexes, value, map_size(indexes))
        prefix = :binary.part(bytes, offset, start - offset)
        {Map.put_new(indexes, value, index), [index, prefix | reversed], start + byte_size(value)}
      end)

    entries =
      indexes
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.map(&elem(&1, 0))
      |> List.to_tuple()

    {entries, Enum.reverse(reversed, [:binary.part(bytes, offset, byte_size(bytes) - offset)])}
  end

  defp collect_identities(%Identity{} = identity, acc), do: MapSet.put(acc, identity)

  defp collect_identities(value, acc) when is_map(value) do
    :maps.fold(fn key, item, found -> collect_identities(item, collect_identities(key, found)) end, acc, value)
  end

  defp collect_identities([head | tail], acc), do: collect_identities(tail, collect_identities(head, acc))

  defp collect_identities(value, acc) when is_tuple(value),
    do: value |> Tuple.to_list() |> Enum.reduce(acc, &collect_identities/2)

  defp collect_identities(_value, acc), do: acc
end
