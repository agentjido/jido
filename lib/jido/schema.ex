defmodule Jido.Schema do
  @moduledoc false

  @doc false
  @spec validate_config_schema(term(), keyword()) :: :ok | {:error, String.t()}
  def validate_config_schema(value, _opts \\ [])

  def validate_config_schema([], _opts), do: :ok

  def validate_config_schema(value, _opts) do
    if zoi_schema?(value) do
      :ok
    else
      {:error, "must be a Zoi schema"}
    end
  end

  @doc false
  @spec zoi_schema?(term()) :: boolean()
  def zoi_schema?(value) do
    is_struct(value) and Zoi.Type.impl_for(value) != nil
  rescue
    _error -> false
  end

  @doc false
  @spec ensure_static_schema!(term(), atom(), Macro.Env.t()) :: term() | no_return()
  def ensure_static_schema!(schema, option, env) do
    case static_schema_data(schema, []) do
      :ok ->
        :ok

      {:error, reason} ->
        raise CompileError,
          description:
            "#{inspect(option)} must be static module data; #{reason}. " <>
              "Use named MFA effects such as {Module, :function, args}",
          file: env.file,
          line: env.line
    end

    try do
      Macro.escape(schema)
      schema
    rescue
      ArgumentError ->
        raise CompileError,
          description:
            "#{inspect(option)} must be static module data that can be stored in the module. " <>
              "Use named MFA effects such as {Module, :function, args}",
          file: env.file,
          line: env.line
    end
  end

  defp static_schema_data(%Zoi.Types.Lazy{}, path),
    do: static_data_error("lazy schemas are not supported", path)

  defp static_schema_data(%Zoi.Types.Meta{} = meta, path) do
    with :ok <- static_schema_effects(meta.effects, path ++ [:effects]) do
      meta
      |> Map.from_struct()
      |> Map.delete(:effects)
      |> static_schema_data(path)
    end
  end

  defp static_schema_data(term, path) when is_function(term),
    do: static_data_error("anonymous functions are not supported", path)

  defp static_schema_data(term, path)
       when is_pid(term) or is_port(term) or is_reference(term),
       do: static_data_error("runtime process values are not supported", path)

  defp static_schema_data(term, path) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.sort_by(fn {key, _value} -> :erlang.term_to_binary(key) end)
    |> Enum.reduce_while(:ok, fn {key, value}, :ok ->
      with :ok <- static_schema_data(key, path ++ [:key]),
           :ok <- static_schema_data(value, path ++ [key]) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp static_schema_data(term, path) when is_list(term) do
    static_schema_list_data(term, path, 0)
  end

  defp static_schema_data(term, path) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case static_schema_data(value, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp static_schema_data(_term, _path), do: :ok

  defp static_schema_effects(effects, path) when is_list(effects) do
    effects
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {effect, index}, :ok ->
      case static_schema_effect(effect, path ++ [index]) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp static_schema_effects(_effects, path),
    do: static_data_error("schema effects must be a list", path)

  defp static_schema_effect({kind, {module, function, args}}, path)
       when kind in [:refine, :transform] and is_atom(module) and is_atom(function) and
              is_list(args) do
    static_schema_data(args, path ++ [kind, :args])
  end

  defp static_schema_effect({kind, effect}, path)
       when kind in [:refine, :transform] and is_function(effect) do
    static_data_error("anonymous functions are not supported", path)
  end

  defp static_schema_effect(_effect, path) do
    static_data_error(
      "custom schema effects must use {Module, :function, args} MFA values",
      path
    )
  end

  defp static_schema_list_data([], _path, _index), do: :ok

  defp static_schema_list_data([value | rest], path, index) when is_list(rest) do
    case static_schema_data(value, path ++ [index]) do
      :ok -> static_schema_list_data(rest, path, index + 1)
      {:error, reason} -> {:error, reason}
    end
  end

  defp static_schema_list_data([value | _tail], path, index) do
    with :ok <- static_schema_data(value, path ++ [index]) do
      static_data_error("improper list tails are not supported", path ++ [index + 1])
    end
  end

  defp static_data_error(reason, []), do: {:error, reason}
  defp static_data_error(reason, path), do: {:error, "#{reason} at #{inspect(path)}"}
end
