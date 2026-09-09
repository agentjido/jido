defmodule Jido.PortableTerm do
  @moduledoc false

  @max_path_segments 20
  @max_binary_segment_bytes 64

  @type path :: [term()]

  @spec validate(term(), atom() | path()) :: :ok | {:error, path()}
  def validate(term, root) when is_atom(root), do: validate(term, [root])

  def validate(term, root) when is_list(root) do
    validate_term(term, Enum.take(root, @max_path_segments))
  end

  @spec valid?(term()) :: boolean()
  def valid?(term), do: validate(term, []) == :ok

  defp validate_term(term, path)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: {:error, path}

  defp validate_term(term, path) when is_bitstring(term) and not is_binary(term),
    do: {:error, path}

  defp validate_term(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{key, value}, index}, :ok ->
      key_path = append(path, {:map_key, index})
      value_path = append(path, path_segment(key, index))

      case validate_term(key, key_path) do
        :ok ->
          case validate_term(value, value_path) do
            :ok -> {:cont, :ok}
            {:error, _path} = error -> {:halt, error}
          end

        {:error, _path} = error ->
          {:halt, error}
      end
    end)
  end

  defp validate_term(term, path) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case validate_term(value, append(path, index)) do
        :ok -> {:cont, :ok}
        {:error, _path} = error -> {:halt, error}
      end
    end)
  end

  defp validate_term([], _path), do: :ok
  defp validate_term([head | tail], path), do: validate_list(head, tail, path, 0)
  defp validate_term(_term, _path), do: :ok

  defp validate_list(head, tail, path, index) do
    case validate_term(head, append(path, index)) do
      :ok -> validate_list_tail(tail, path, index + 1)
      {:error, _path} = error -> error
    end
  end

  defp validate_list_tail([], _path, _index), do: :ok

  defp validate_list_tail([head | tail], path, index),
    do: validate_list(head, tail, path, index)

  defp validate_list_tail(_improper_tail, path, index),
    do: {:error, append(path, index)}

  defp append(path, _segment) when length(path) >= @max_path_segments, do: path
  defp append(path, segment), do: path ++ [segment]

  defp path_segment(key, _index) when is_atom(key) or is_integer(key), do: key

  defp path_segment(key, _index) when is_binary(key) do
    if byte_size(key) <= @max_binary_segment_bytes,
      do: key,
      else: binary_part(key, 0, @max_binary_segment_bytes)
  end

  defp path_segment(_key, index), do: {:map_value, index}
end
