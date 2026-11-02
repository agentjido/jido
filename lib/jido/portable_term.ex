defmodule Jido.PortableTerm do
  @moduledoc """
  Validates terms that must be portable between BEAM instances.

  This module is a shared lower-layer contract. Use it before you store or
  transmit an Erlang term that another BEAM instance must read.

  The validator rejects PIDs, ports, references, functions, improper lists,
  and non-byte-aligned bitstrings. It checks nested map keys, map values,
  tuples, and lists. On failure, it returns a bounded path to the first value
  that it rejects.

  This strict storage policy is different from the managed execution policy
  in `Jido.Exec`. Managed execution uses an internal traversal mode that
  permits improper lists and non-byte-aligned bitstrings.
  """

  @max_path_segments 20
  @max_binary_segment_bytes 64
  @max_path_integer 9_999_999_999_999_999

  @typedoc "A bounded path to a rejected value."
  @type path :: [term()]

  @typep local_type :: :pid | :port | :reference | :function
  @typep rejection_type :: local_type() | :bitstring | :improper_list
  @typep policy :: :strict | :local

  @doc """
  Validates one term and returns the path to the first rejected value.

  The root can be an atom or an existing path. An invalid root returns
  `{:error, []}`.
  """
  @spec validate(term(), atom() | path()) :: :ok | {:error, path()}
  def validate(term, root) when is_atom(root), do: validate_root(term, [root])

  def validate(term, root) when is_list(root), do: validate_root(term, root)

  def validate(_term, _root), do: {:error, []}

  defp validate_root(term, root) do
    path =
      root
      |> Enum.take(@max_path_segments)
      |> Enum.with_index()
      |> Enum.map(fn {segment, index} -> path_segment(segment, index) end)

    case walk(term, path, :strict) do
      :ok -> :ok
      {:error, _type, path} -> {:error, path}
    end
  end

  @doc false
  @spec validate_local(term(), atom()) :: :ok | {:error, local_type(), [term()]}
  def validate_local(term, root) when is_atom(root), do: walk(term, [root], :local)

  @doc "Returns `true` when `validate/2` accepts the term."
  @spec valid?(term()) :: boolean()
  def valid?(term), do: validate(term, []) == :ok

  @spec walk(term(), [term()], policy()) :: :ok | {:error, rejection_type(), [term()]}
  defp walk(term, path, _policy)
       when is_pid(term) or is_reference(term) or is_port(term) or is_function(term),
       do: {:error, local_type(term), path}

  defp walk(term, path, :strict) when is_bitstring(term) and not is_binary(term),
    do: {:error, :bitstring, path}

  defp walk(term, path, :strict) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {{key, value}, index}, :ok ->
      key_path = append(path, {:map_key, index}, :strict)
      value_path = append(path, path_segment(key, index), :strict)

      with :ok <- walk(key, key_path, :strict),
           :ok <- walk(value, value_path, :strict) do
        {:cont, :ok}
      else
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk(term, path, :local) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      with :ok <- walk(key, path ++ [:key], :local),
           :ok <- walk(value, path ++ [key], :local) do
        {:cont, :ok}
      else
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk(term, path, policy) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case walk(value, append(path, index, policy), policy) do
        :ok -> {:cont, :ok}
        {:error, _type, _path} = error -> {:halt, error}
      end
    end)
  end

  defp walk([], _path, _policy), do: :ok
  defp walk([head | tail], path, :strict), do: walk_strict_list(head, tail, path, 0)
  defp walk([_head | _tail] = term, path, :local), do: walk_local_list(term, path, 0)
  defp walk(_term, _path, _policy), do: :ok

  defp walk_strict_list(head, tail, path, index) do
    case walk(head, append(path, index, :strict), :strict) do
      :ok -> walk_strict_list_tail(tail, path, index + 1)
      {:error, _type, _path} = error -> error
    end
  end

  defp walk_strict_list_tail([], _path, _index), do: :ok

  defp walk_strict_list_tail([head | tail], path, index),
    do: walk_strict_list(head, tail, path, index)

  defp walk_strict_list_tail(_improper_tail, path, index),
    do: {:error, :improper_list, append(path, index, :strict)}

  defp walk_local_list([], _path, _index), do: :ok

  defp walk_local_list([value | rest], path, index) do
    case walk(value, append(path, index, :local), :local) do
      :ok when is_list(rest) -> walk_local_list(rest, path, index + 1)
      :ok -> walk(rest, append(path, :tail, :local), :local)
      {:error, _type, _path} = error -> error
    end
  end

  defp append(path, _segment, :strict) when length(path) >= @max_path_segments, do: path
  defp append(path, segment, _policy), do: path ++ [segment]

  defp local_type(term) when is_pid(term), do: :pid
  defp local_type(term) when is_port(term), do: :port
  defp local_type(term) when is_reference(term), do: :reference
  defp local_type(term) when is_function(term), do: :function

  defp path_segment(key, _index) when is_atom(key) do
    key
    |> Atom.to_string()
    |> bounded_segment(key)
  end

  defp path_segment(key, _index)
       when is_integer(key) and key >= -@max_path_integer and key <= @max_path_integer,
       do: key

  defp path_segment(key, index) when is_integer(key), do: {:map_value, index}

  defp path_segment(key, _index) when is_binary(key) do
    bounded_segment(key, key)
  end

  defp path_segment(_key, index), do: {:map_value, index}

  defp bounded_segment(encoded, original) do
    if byte_size(encoded) <= @max_binary_segment_bytes,
      do: original,
      else: binary_part(encoded, 0, @max_binary_segment_bytes)
  end
end
