defmodule Jido.Log do
  @moduledoc false

  require Logger

  @default_max_length 200

  @type metadata :: keyword()

  @spec debug(Logger.message(), metadata()) :: :ok
  def debug(message, metadata \\ []), do: Logger.debug(message, metadata)

  @spec info(Logger.message(), metadata()) :: :ok
  def info(message, metadata \\ []), do: Logger.info(message, metadata)

  @spec warning(Logger.message(), metadata()) :: :ok
  def warning(message, metadata \\ []), do: Logger.warning(message, metadata)

  @spec error(Logger.message(), metadata()) :: :ok
  def error(message, metadata \\ []), do: Logger.error(message, metadata)

  @spec safe_inspect(term(), keyword()) :: String.t()
  def safe_inspect(term, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @default_max_length)
    limit = Keyword.get(opts, :limit, 10)

    term
    |> inspect(limit: limit, printable_limit: max_length, width: max_length)
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
