defmodule Jido.Exec.Frame.Delta.Reference do
  @moduledoc false

  @enforce_keys [:path]
  defstruct [:path]

  @type segment :: {:map, term()} | {:tuple, non_neg_integer()} | {:list, non_neg_integer()}
  @type t :: %__MODULE__{path: [segment()]}
end

defmodule Jido.Exec.Frame.Delta.Literal do
  @moduledoc false

  @enforce_keys [:value]
  defstruct [:value]

  @type t :: %__MODULE__{value: term()}
end

defmodule Jido.Exec.Frame.Delta do
  @moduledoc false

  alias Jido.Exec.Frame.Delta.{Literal, Reference}

  @tag :jido_frame_delta
  @version 1
  @min_binary_bytes 64

  @type encoded :: {:jido_frame_delta, 1, term()}
  @type encode_result :: {:delta, encoded()} | :full

  @doc false
  @spec encode(term(), term()) :: encode_result()
  def encode(parent, child) do
    template = encode_value(child, build_index(parent))
    encoded = {@tag, @version, template}

    if encoded_size(encoded) < encoded_size(child), do: {:delta, encoded}, else: :full
  end

  @doc false
  @spec decode(term(), encoded()) :: {:ok, term()} | {:error, term()}
  def decode(parent, {@tag, @version, template}), do: decode_value(template, parent)
  def decode(_parent, _encoded), do: {:error, :invalid_frame_delta}

  defp build_index(parent), do: index_value(parent, [], %{})

  defp index_value(value, path, index) do
    index =
      if candidate?(value) do
        Map.update(index, index_key(value), [{path, value}], &[{path, value} | &1])
      else
        index
      end

    index_children(value, path, index)
  end

  defp index_children(value, path, index) when is_map(value) do
    value
    |> ordered_map_entries()
    |> Enum.reduce(index, fn {key, item}, current ->
      index_value(item, path ++ [{:map, key}], current)
    end)
  end

  defp index_children(value, path, index) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce(index, fn {item, position}, current ->
      index_value(item, path ++ [{:tuple, position}], current)
    end)
  end

  defp index_children(value, path, index) when is_list(value) do
    if List.improper?(value) do
      index
    else
      value
      |> Enum.with_index()
      |> Enum.reduce(index, fn {item, position}, current ->
        index_value(item, path ++ [{:list, position}], current)
      end)
    end
  end

  defp index_children(_value, _path, index), do: index

  defp encode_value(value, index) do
    case parent_reference(value, index) do
      nil -> encode_children(value, index)
      reference -> reference
    end
  end

  defp encode_children(%module{} = value, _index) when module in [Literal, Reference],
    do: %Literal{value: value}

  defp encode_children(value, index) when is_map(value) do
    value
    |> ordered_map_entries()
    |> Map.new(fn {key, item} -> {key, encode_value(item, index)} end)
  end

  defp encode_children(value, index) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&encode_value(&1, index))
    |> List.to_tuple()
  end

  defp encode_children(value, index) when is_list(value) do
    if List.improper?(value), do: value, else: Enum.map(value, &encode_value(&1, index))
  end

  defp encode_children(value, _index), do: value

  defp parent_reference(value, index) do
    candidates = if candidate?(value), do: Map.get(index, index_key(value), []), else: []

    if candidates == [] do
      nil
    else
      value_size = encoded_size(value)

      candidates
      |> Enum.reduce([], fn {path, candidate}, references ->
        if candidate === value do
          reference = %Reference{path: path}
          reference_size = encoded_size(reference)

          if reference_size < value_size,
            do: [{reference_size, encoded_path(path), reference} | references],
            else: references
        else
          references
        end
      end)
      |> Enum.min_by(fn {size, path, _reference} -> {size, path} end, fn -> nil end)
      |> case do
        nil -> nil
        {_size, _path, reference} -> reference
      end
    end
  end

  defp decode_value(%Literal{value: value}, _parent), do: {:ok, value}
  defp decode_value(%Reference{path: path}, parent), do: fetch_parent(parent, path)

  defp decode_value(value, parent) when is_map(value) do
    value
    |> ordered_map_entries()
    |> Enum.reduce_while({:ok, %{}}, fn {key, item}, {:ok, decoded} ->
      case decode_value(item, parent) do
        {:ok, value} -> {:cont, {:ok, Map.put(decoded, key, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp decode_value(value, parent) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> decode_list(parent)
    |> case do
      {:ok, items} -> {:ok, List.to_tuple(items)}
      {:error, _reason} = error -> error
    end
  end

  defp decode_value(value, parent) when is_list(value) do
    if List.improper?(value), do: {:ok, value}, else: decode_list(value, parent)
  end

  defp decode_value(value, _parent), do: {:ok, value}

  defp decode_list(items, parent) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, decoded} ->
      case decode_value(item, parent) do
        {:ok, value} -> {:cont, {:ok, [value | decoded]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, decoded} -> {:ok, Enum.reverse(decoded)}
      {:error, _reason} = error -> error
    end
  end

  defp fetch_parent(parent, path) when is_list(path) do
    result =
      Enum.reduce_while(path, {:ok, parent}, fn segment, {:ok, current} ->
        case fetch_segment(current, segment) do
          {:ok, value} -> {:cont, {:ok, value}}
          :error -> {:halt, :error}
        end
      end)

    case result do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:invalid_parent_reference, path}}
    end
  end

  defp fetch_parent(_parent, path), do: {:error, {:invalid_parent_reference, path}}

  defp fetch_segment(value, {:map, key}) when is_map(value), do: Map.fetch(value, key)

  defp fetch_segment(value, {:tuple, position})
       when is_tuple(value) and is_integer(position) and position >= 0 and
              position < tuple_size(value),
       do: {:ok, elem(value, position)}

  defp fetch_segment(value, {:list, position})
       when is_list(value) and is_integer(position) and position >= 0 do
    if List.improper?(value), do: :error, else: Enum.fetch(value, position)
  end

  defp fetch_segment(_value, _segment), do: :error

  defp candidate?(value) when is_binary(value), do: byte_size(value) >= @min_binary_bytes
  defp candidate?(value) when is_map(value), do: map_size(value) > 0
  defp candidate?(value) when is_tuple(value), do: tuple_size(value) > 0

  defp candidate?(value) when is_list(value),
    do: value != [] and not List.improper?(value)

  defp candidate?(_value), do: false

  defp index_key(value), do: {term_kind(value), :erlang.phash2(value)}

  defp term_kind(value) when is_binary(value), do: :binary
  defp term_kind(value) when is_map(value), do: :map
  defp term_kind(value) when is_tuple(value), do: :tuple
  defp term_kind(value) when is_list(value), do: :list

  defp ordered_map_entries(map) do
    map
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} ->
      :erlang.term_to_binary(key, [:deterministic])
    end)
  end

  defp encoded_path(path), do: :erlang.term_to_binary(path, [:deterministic])
  defp encoded_size(value), do: value |> :erlang.term_to_binary([:deterministic]) |> byte_size()
end
