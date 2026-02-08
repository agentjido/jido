defmodule Jido.Observe.Log do
  @moduledoc """
  Centralized log threshold for observability.

  This module provides threshold-based logging for Jido's observability system.
  The log threshold can be configured per-environment to control verbosity:

  - `:debug` in development for verbose output
  - `:info` or `:warning` in production for minimal noise

  ## Configuration

      # config/config.exs
      config :jido, :observability,
        log_level: :info
      
      # config/dev.exs
      config :jido, :observability,
        log_level: :debug

  ## Usage

      alias Jido.Observe.Log
      
      # Only logs if threshold allows :debug level
      Log.log(:debug, "Processing step", agent_id: agent.id, step: 1)
      
      # Always logs in most configurations
      Log.log(:info, "Agent completed", agent_id: agent.id)
  """

  require Logger

  @default_log_level :info
  @telemetry_compatible_levels [:trace, :debug, :info, :warning, :error]
  @logger_levels Logger.levels()

  @type level :: :trace | :debug | :info | :warning | :error

  @doc """
  Returns the current observability log threshold.

  Reads from application config `:jido, :observability, :log_level`.
  Defaults to `:info` if not configured.
  """
  @spec threshold() :: level()
  def threshold do
    Jido.Observe.observability_config()
    |> Keyword.get(:log_level, @default_log_level)
    |> normalize_level()
  end

  @doc """
  Conditionally logs a message based on the observability threshold.

  The message is logged only if the threshold level allows it.
  Uses `Jido.Util.cond_log/4` under the hood.

  ## Parameters

  - `level` - The log level for this message (:debug, :info, :warning, :error)
  - `message` - The message to log (string or iodata)
  - `metadata` - Keyword list of metadata to include

  ## Examples

      # With threshold at :info, this won't log
      Log.log(:debug, "Verbose info", step: 1)
      
      # With threshold at :info, this will log
      Log.log(:info, "Important info", agent_id: "abc")
  """
  @spec log(level(), Logger.message(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    Jido.Util.cond_log(
      normalize_for_logger(threshold()),
      normalize_for_logger(level),
      message,
      metadata
    )
  end

  defp normalize_level(level) when level in @telemetry_compatible_levels, do: level
  defp normalize_level(_), do: @default_log_level

  defp normalize_for_logger(:trace), do: :debug

  defp normalize_for_logger(level) when level in @logger_levels do
    level
  end

  defp normalize_for_logger(_), do: @default_log_level
end
