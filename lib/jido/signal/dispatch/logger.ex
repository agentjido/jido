defmodule Jido.Signal.Dispatch.LoggerAdapter do
  @moduledoc """
  An adapter for dispatching signals through Elixir's Logger system.

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to log signals using Elixir's built-in Logger. It supports both
  structured and unstructured logging formats and respects configured log levels.

  ## Configuration Options

  * `:level` - (optional) The log level to use, one of [:debug, :info, :warning, :error], defaults to `:info`
  * `:structured` - (optional) Whether to use structured logging format, defaults to `false`

  ## Logging Formats

  ### Unstructured (default)
  ```
  Signal dispatched: signal_type from source with data={...}
  ```

  ### Structured
  ```elixir
  %{
    event: "signal_dispatched",
    id: "signal_id",
    type: "signal_type",
    data: {...},
    source: "source"
  }
  ```

  ## Examples

      # Basic usage with default level
      config = {:logger, []}

      # Custom log level
      config = {:logger, [
        level: :debug
      ]}

      # Structured logging
      config = {:logger, [
        level: :info,
        structured: true
      ]}

  ## Integration with Logger

  The adapter integrates with Elixir's Logger system, which means:
  * Log messages respect the global Logger configuration
  * Metadata and formatting can be customized through Logger backends
  * Log levels can be filtered at runtime
  * Structured logging can be processed by log aggregators

  ## Notes

  * Consider using structured logging when integrating with log aggregation systems
  * Log levels should be chosen based on the signal's importance
  * High-volume signals should use `:debug` level to avoid log spam
  """

  @behaviour Jido.Signal.Dispatch.Adapter
  require Logger

  @valid_levels [:debug, :info, :warning, :error]

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the logger adapter configuration options.

  ## Parameters

  * `opts` - Keyword list of options to validate

  ## Options

  * `:level` - (optional) One of #{inspect(@valid_levels)}, defaults to `:info`
  * `:structured` - (optional) Boolean, defaults to `false`

  ## Returns

  * `{:ok, validated_opts}` - Options are valid
  * `{:error, reason}` - Options are invalid with string reason
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()} | {:error, String.t()}
  def validate_opts(opts) do
    level = Keyword.get(opts, :level, :info)

    if level in @valid_levels do
      {:ok, opts}
    else
      {:error, "Invalid log level: #{inspect(level)}. Must be one of #{inspect(@valid_levels)}"}
    end
  end

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Logs a signal using the configured format and level.

  ## Parameters

  * `signal` - The signal to log
  * `opts` - Validated options from `validate_opts/1`

  ## Options

  * `:level` - (optional) The log level to use, defaults to `:info`
  * `:structured` - (optional) Whether to use structured format, defaults to `false`

  ## Returns

  * `:ok` - Signal was logged successfully

  ## Examples

      iex> signal = %Jido.Signal{type: "user:created", data: %{id: 123}}
      iex> LoggerAdapter.deliver(signal, [level: :info])
      :ok
      # Logs: "Signal dispatched: user:created from source with data=%{id: 123}"

      iex> LoggerAdapter.deliver(signal, [level: :info, structured: true])
      :ok
      # Logs structured map with event details
  """
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(signal, opts) do
    level = Keyword.get(opts, :level, :info)
    structured = Keyword.get(opts, :structured, false)

    if structured do
      Logger.log(
        level,
        fn ->
          %{
            event: "signal_dispatched",
            id: signal.id,
            type: signal.type,
            data: signal.data,
            source: signal.source
          }
        end,
        []
      )
    else
      Logger.log(
        level,
        "Signal dispatched: #{signal.type} from #{signal.source} with data=#{inspect(signal.data)}",
        []
      )
    end

    :ok
  end
end
