defmodule Jido.Config do
  @moduledoc """
  Deferred environment references for runtime configuration.

  `env/1` stores a variable name as `{:env, name}`. It does not read the
  environment. `use Jido.Agent` imports this helper for DSL declarations.
  Map authoring uses `Jido.Config.env/1` or the same tuple.

  A runtime consumer calls `resolve/1` when it starts its resources. Keep the
  resolved configuration in that runtime. Agent definitions, JSON documents,
  and snapshots retain the references. A replacement runtime resolves them
  again from the current environment.

  The host application owns environment file loading. This module reads
  variables with `System.fetch_env/1` and does not load files or convert values.
  The consumer validates the resolved configuration with its own schema.
  """

  alias Jido.Error

  @typedoc "A required environment variable whose value is read at runtime."
  @type env_reference :: {:env, String.t()}

  @doc """
  Creates a deferred reference without reading the environment.

  Raises `ArgumentError` if the name is empty, is not a UTF-8 string, or
  contains `=` or a null byte.

      iex> Jido.Config.env("API_KEY")
      {:env, "API_KEY"}
  """
  @spec env(String.t()) :: env_reference()
  def env(name) do
    if valid_name?(name),
      do: {:env, name},
      else: raise(ArgumentError, "env/1 requires a nonempty environment variable name")
  end

  @doc """
  Resolves environment references in configuration values.

  Walks plain map values, lists, keyword lists, and tuples. Preserves map keys,
  keyword order, duplicate keyword entries, and tuple shape. Structs and other
  values are unchanged. Environment values remain strings, including empty
  strings. `{:env, name}` is reserved, including in lists such as
  `[env("ROOM_ID")]`; an `:env` keyword entry has the same reference meaning.

  Missing variables return `Jido.Error.ValidationError` with `kind: :config`
  and details `%{code: :missing_env, name: name, path: path}`. Invalid reference
  names return details `%{code: :invalid_env, path: path}`. Paths contain map
  or keyword keys and zero-based list or tuple indices. Errors do not include
  the complete configuration or resolved values. Improper lists return code
  `:invalid_config` and the path of the invalid tail.
  """
  @spec resolve(term()) :: {:ok, term()} | {:error, Error.ValidationError.t()}
  def resolve(value), do: resolve(value, [])

  defp resolve({:env, name}, path) do
    if valid_name?(name) do
      case System.fetch_env(name) do
        {:ok, value} -> {:ok, value}
        :error -> error("Required environment variable is missing", :missing_env, path, name)
      end
    else
      error("Invalid environment variable reference", :invalid_env, path)
    end
  end

  defp resolve(value, _path) when is_struct(value), do: {:ok, value}

  defp resolve(value, path) when is_map(value) do
    with {:ok, pairs} <- resolve_pairs(Enum.sort(value), path), do: {:ok, Map.new(pairs)}
  end

  defp resolve(value, path) when is_list(value) do
    if Keyword.keyword?(value) and not Keyword.has_key?(value, :env),
      do: resolve_pairs(value, path),
      else: resolve_list(value, path, 0)
  end

  defp resolve(value, path) when is_tuple(value) do
    with {:ok, values} <- resolve_list(Tuple.to_list(value), path, 0),
         do: {:ok, List.to_tuple(values)}
  end

  defp resolve(value, _path), do: {:ok, value}

  defp resolve_pairs([], _path), do: {:ok, []}

  defp resolve_pairs([{key, value} | rest], path) do
    with {:ok, value} <- resolve(value, path ++ [key]),
         {:ok, rest} <- resolve_pairs(rest, path),
         do: {:ok, [{key, value} | rest]}
  end

  defp resolve_list([], _path, _index), do: {:ok, []}

  defp resolve_list([value | rest], path, index) do
    with {:ok, value} <- resolve(value, path ++ [index]),
         {:ok, rest} <- resolve_list(rest, path, index + 1),
         do: {:ok, [value | rest]}
  end

  defp resolve_list(_tail, path, index),
    do: error("Configuration lists must be proper lists", :invalid_config, path ++ [index])

  defp valid_name?(name) when is_binary(name),
    do: name != "" and String.valid?(name) and not String.contains?(name, ["=", <<0>>])

  defp valid_name?(_name), do: false

  defp error(message, code, path, name \\ nil) do
    details = %{code: code, path: path}
    details = if name, do: Map.put(details, :name, name), else: details
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end
