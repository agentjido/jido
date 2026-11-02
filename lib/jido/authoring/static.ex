defmodule Jido.Authoring.Static do
  @moduledoc false

  @doc false
  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(term), do: validate(term, [])

  defp validate(%Zoi.Types.Lazy{}, path),
    do: error("lazy schemas are not supported", path)

  defp validate(term, path) when is_function(term),
    do: error("anonymous functions are not supported", path)

  defp validate(term, path) when is_pid(term) or is_port(term) or is_reference(term),
    do: error("runtime process values are not supported", path)

  defp validate(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
    |> validate_pairs(path)
  end

  defp validate(term, path) when is_list(term), do: validate_list(term, path, 0)
  defp validate(term, path) when is_tuple(term), do: validate_list(Tuple.to_list(term), path, 0)
  defp validate(_term, _path), do: :ok

  defp validate_pairs([], _path), do: :ok

  defp validate_pairs([{key, value} | rest], path) do
    with :ok <- validate(key, path ++ [:key]),
         :ok <- validate(value, path ++ [key]),
         do: validate_pairs(rest, path)
  end

  defp validate_list([], _path, _index), do: :ok

  defp validate_list([value | rest], path, index) when is_list(rest) do
    with :ok <- validate(value, path ++ [index]),
         do: validate_list(rest, path, index + 1)
  end

  defp validate_list([value | _tail], path, index) do
    with :ok <- validate(value, path ++ [index]),
         do: error("improper list tails are not supported", path ++ [index + 1])
  end

  defp error(reason, []), do: {:error, reason}
  defp error(reason, path), do: {:error, "#{reason} at #{inspect(path)}"}
end
