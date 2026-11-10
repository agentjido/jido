defmodule Jido.Codec.Term do
  @moduledoc """
  Validates Erlang terms that must cross a BEAM storage boundary.

  The validator rejects PIDs, ports, references, functions, improper lists,
  and non-byte-aligned bitstrings. It checks nested map keys, map values,
  tuples, and lists. On failure, it returns a bounded path to the first value
  that it rejects.

  This strict storage policy is different from the local-value policy in
  `Jido.Exec.Runtime`. Managed execution permits improper lists and
  non-byte-aligned bitstrings, but it rejects process-local values.
  """

  @max_path_segments 20
  @max_binary_segment_bytes 64
  @max_path_integer 9_999_999_999_999_999

  @typedoc "A bounded path to a rejected value."
  @type path :: [term()]

  @doc """
  Validates one term and returns the path to the first rejected value.

  The root can be an atom or an existing path. An invalid root returns
  `{:error, []}`.
  """
  @spec validate(term(), atom() | path()) :: :ok | {:error, path()}
  def validate(term, root) when is_atom(root), do: validate_root(term, [root])
  def validate(term, root) when is_list(root), do: validate_root(term, root)
  def validate(_term, _root), do: {:error, []}

  @doc "Returns `true` when `validate/2` accepts the term."
  @spec valid?(term()) :: boolean()
  def valid?(term), do: validate(term, []) == :ok

  defp validate_root(term, root) do
    path =
      root
      |> Enum.take(@max_path_segments)
      |> Enum.with_index()
      |> Enum.map(fn {segment, index} -> path_segment(segment, index) end)

    walk(term, path)
  end

  defp walk(term, path)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: {:error, path}

  defp walk(term, path) when is_bitstring(term) and not is_binary(term),
    do: {:error, path}

  defp walk(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{key, value}, index}, :ok ->
      with :ok <- walk(key, append(path, {:map_key, index})),
           :ok <- walk(value, append(path, path_segment(key, index))) do
        {:cont, :ok}
      else
        {:error, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk(term, path) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case walk(value, append(path, index)) do
        :ok -> {:cont, :ok}
        {:error, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk([], _path), do: :ok
  defp walk([head | tail], path), do: walk_list(head, tail, path, 0)
  defp walk(_term, _path), do: :ok

  defp walk_list(head, tail, path, index) do
    case walk(head, append(path, index)) do
      :ok -> walk_list_tail(tail, path, index + 1)
      {:error, _path} = error -> error
    end
  end

  defp walk_list_tail([], _path, _index), do: :ok
  defp walk_list_tail([head | tail], path, index), do: walk_list(head, tail, path, index)
  defp walk_list_tail(_improper_tail, path, index), do: {:error, append(path, index)}

  defp append(path, _segment) when length(path) >= @max_path_segments, do: path
  defp append(path, segment), do: path ++ [segment]

  defp path_segment(key, _index) when is_atom(key) do
    key
    |> Atom.to_string()
    |> bounded_segment(key)
  end

  defp path_segment(key, _index)
       when is_integer(key) and key >= -@max_path_integer and key <= @max_path_integer,
       do: key

  defp path_segment(key, index) when is_integer(key), do: {:map_value, index}

  defp path_segment(key, _index) when is_binary(key), do: bounded_segment(key, key)
  defp path_segment(_key, index), do: {:map_value, index}

  defp bounded_segment(encoded, original) do
    if byte_size(encoded) <= @max_binary_segment_bytes,
      do: original,
      else: binary_part(encoded, 0, @max_binary_segment_bytes)
  end
end
