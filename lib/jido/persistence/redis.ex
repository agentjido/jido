defmodule Jido.Persistence.Redis do
  @moduledoc """
  Redis persistence adapter for binary keys and values.

  The required `:command_fn` option executes one Redis command. The optional
  `:prefix` defaults to `"jido"`. Records do not expire automatically.

  Conditional writes use one Lua `EVAL` command to compare and replace the
  value atomically. The Redis connection must permit EVAL.
  """

  @behaviour Jido.Persistence.Store

  @default_prefix "jido"

  @compare_and_swap """
  local current = redis.call('GET', KEYS[1])
  if ARGV[1] == 'missing' then
    if current then return 0 end
  elseif current ~= ARGV[2] then
    return 0
  end
  redis.call('SET', KEYS[1], ARGV[3])
  return 1
  """

  @impl true
  def validate_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, "options must be a keyword list"}

      Keyword.keys(opts) -- [:command_fn, :prefix] != [] ->
        {:error, "supports only :command_fn and :prefix options"}

      Keyword.keys(opts) -- Enum.uniq(Keyword.keys(opts)) != [] ->
        {:error, "options must be unique"}

      not is_function(Keyword.get(opts, :command_fn), 1) ->
        {:error, "requires a :command_fn option"}

      not is_binary(Keyword.get(opts, :prefix, @default_prefix)) ->
        {:error, ":prefix must be a string"}

      true ->
        :ok
    end
  end

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)
    command_fn = Keyword.fetch!(opts, :command_fn)

    case command_fn.(["GET", redis_key(key, opts)]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    validate_options!(opts)
    command_fn = Keyword.fetch!(opts, :command_fn)

    case command_fn.(["SET", redis_key(key, opts), value]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    validate_options!(opts)
    command_fn = Keyword.fetch!(opts, :command_fn)
    {mode, previous} = if expected == :not_found, do: {"missing", ""}, else: {"value", expected}
    command = ["EVAL", @compare_and_swap, "1", redis_key(key, opts), mode, previous, value]

    case command_fn.(command) do
      {:ok, 1} -> :ok
      {:ok, 0} -> {:error, :conflict}
      {:error, reason} -> {:error, {:indeterminate, reason}}
      result -> {:error, {:indeterminate, {:invalid_redis_result, result}}}
    end
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    validate_options!(opts)
    command_fn = Keyword.fetch!(opts, :command_fn)

    case command_fn.(["DEL", redis_key(key, opts)]) do
      {:ok, deleted} when is_integer(deleted) and deleted >= 0 -> :ok
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  defp redis_key(key, opts), do: "#{Keyword.get(opts, :prefix, @default_prefix)}:#{key}"

  defp validate_options!(opts) do
    case validate_options(opts) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, "Jido.Persistence.Redis #{reason}"
    end
  end
end
