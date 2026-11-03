defmodule Jido.Codec.Static do
  alias Jido.Joi
  @moduledoc false

  @doc false
  @spec validate(term()) :: :ok | {:error, String.t()}
  def validate(term), do: validate(term, [])

  defp validate(term, path) when is_function(term),
    do: error("anonymous functions are not supported", path)

  defp validate(term, path) when is_pid(term) or is_port(term) or is_reference(term),
    do: error("runtime process values are not supported", path)

  defp validate(term, path) when is_map(term) do
    case Joi.Schema.kind(term) do
      :lazy ->
        error("lazy schemas are not supported", path)

      :meta ->
        with :ok <- validate_effects(Joi.Schema.effects(term), path ++ [:effects]) do
          term
          |> Map.from_struct()
          |> Map.delete(:effects)
          |> validate(path)
        end

      _ ->
        term
        |> Map.to_list()
        |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
        |> validate_pairs(path)
    end
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

  defp validate_effects(effects, path) when is_list(effects) do
    effects
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {effect, index}, :ok ->
      case validate_effect(effect, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_effects(_effects, path), do: error("schema effects must be a list", path)

  defp validate_effect({kind, {module, function, args}}, path)
       when kind in [:refine, :transform] and is_atom(module) and is_atom(function) and
              is_list(args),
       do: validate(args, path ++ [1, 2])

  defp validate_effect({kind, effect}, path)
       when kind in [:refine, :transform] and is_function(effect),
       do: error("anonymous functions are not supported", path ++ [1])

  defp validate_effect(_effect, path),
    do: error("custom schema effects must use {Module, :function, args} MFA values", path)

  defp error(reason, []), do: {:error, reason}
  defp error(reason, path), do: {:error, "#{reason} at #{inspect(path)}"}
end
