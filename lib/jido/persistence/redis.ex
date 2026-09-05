defmodule Jido.Persistence.Redis do
  @moduledoc """
  Redis persistence adapter for binary keys and values.

  The required `:command_fn` option executes one Redis command. The optional
  `:prefix` defaults to `"jido"`. The optional `:ttl` sets the key lifetime in
  milliseconds.

  Conditional writes use one Lua `EVAL` command to compare and replace the
  value atomically, including its TTL. The Redis connection must permit EVAL.
  """

  @behaviour Jido.Persistence.Adapter

  @default_prefix "jido"

  @compare_and_swap """
  local current = redis.call('GET', KEYS[1])
  if ARGV[1] == 'missing' then
    if current then return 0 end
  elseif current ~= ARGV[2] then
    return 0
  end
  if ARGV[4] == '' then
    redis.call('SET', KEYS[1], ARGV[3])
  else
    redis.call('SET', KEYS[1], ARGV[3], 'PX', ARGV[4])
  end
  return 1
  """

  @impl true
  def get(key, opts) when is_binary(key) and is_list(opts) do
    command_fn = fetch_command_fn!(opts)

    case command_fn.(["GET", redis_key(key, opts)]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  @impl true
  def put(key, value, opts) when is_binary(key) and is_binary(value) and is_list(opts) do
    command_fn = fetch_command_fn!(opts)

    command =
      case Keyword.get(opts, :ttl) do
        nil -> ["SET", redis_key(key, opts), value]
        ttl -> ["SET", redis_key(key, opts), value, "PX", to_string(ttl)]
      end

    case command_fn.(command) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  @impl true
  def compare_and_swap(key, expected, value, opts)
      when is_binary(key) and (expected == :not_found or is_binary(expected)) and
             is_binary(value) and is_list(opts) do
    command_fn = fetch_command_fn!(opts)
    {mode, previous} = if expected == :not_found, do: {"missing", ""}, else: {"value", expected}
    ttl = opts |> Keyword.get(:ttl) |> encode_ttl!()
    command = ["EVAL", @compare_and_swap, "1", redis_key(key, opts), mode, previous, value, ttl]

    case command_fn.(command) do
      {:ok, 1} -> :ok
      {:ok, 0} -> {:error, :conflict}
      {:error, reason} -> {:error, {:indeterminate, reason}}
      result -> {:error, {:indeterminate, {:invalid_redis_result, result}}}
    end
  end

  @impl true
  def delete(key, opts) when is_binary(key) and is_list(opts) do
    command_fn = fetch_command_fn!(opts)

    case command_fn.(["DEL", redis_key(key, opts)]) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
      result -> {:error, {:invalid_redis_result, result}}
    end
  end

  defp redis_key(key, opts), do: "#{Keyword.get(opts, :prefix, @default_prefix)}:#{key}"

  defp encode_ttl!(nil), do: ""
  defp encode_ttl!(ttl) when is_integer(ttl) and ttl > 0, do: Integer.to_string(ttl)

  defp encode_ttl!(_ttl),
    do: raise(ArgumentError, "Jido.Persistence.Redis :ttl must be a positive integer")

  defp fetch_command_fn!(opts) do
    case Keyword.fetch(opts, :command_fn) do
      {:ok, fun} when is_function(fun, 1) -> fun
      _other -> raise ArgumentError, "Jido.Persistence.Redis requires a :command_fn option"
    end
  end
end
