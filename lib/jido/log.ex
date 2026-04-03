defmodule Jido.Log do
  @moduledoc false

  require Logger

  @default_max_length 200
  @default_limit 10

  @type metadata :: keyword()
  @type level :: Logger.level()

  @doc false
  @spec debug(Logger.message(), metadata()) :: :ok
  def debug(message, metadata \\ []), do: Logger.debug(message, metadata)

  @doc false
  @spec info(Logger.message(), metadata()) :: :ok
  def info(message, metadata \\ []), do: Logger.info(message, metadata)

  @doc false
  @spec warning(Logger.message(), metadata()) :: :ok
  def warning(message, metadata \\ []), do: Logger.warning(message, metadata)

  @doc false
  @spec error(Logger.message(), metadata()) :: :ok
  def error(message, metadata \\ []), do: Logger.error(message, metadata)

  @doc false
  @spec log(level(), Logger.message(), metadata()) :: :ok
  def log(level, message, metadata \\ []), do: Logger.log(level, message, metadata)

  @doc false
  @spec levels() :: [level()]
  def levels, do: Logger.levels()

  @doc false
  @spec compare_levels(level(), level()) :: :lt | :eq | :gt
  def compare_levels(left, right), do: Logger.compare_levels(left, right)

  @doc false
  @spec safe_inspect(term(), keyword()) :: String.t()
  def safe_inspect(term, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @default_max_length)
    limit = Keyword.get(opts, :limit, @default_limit)

    term
    |> inspect(limit: limit, printable_limit: max_length, width: max_length, charlists: :as_lists)
    |> truncate(max_length)
  end

  defp truncate(binary, max_length) when is_binary(binary) do
    if String.length(binary) > max_length do
      String.slice(binary, 0, max_length) <> "..."
    else
      binary
    end
  end
end
