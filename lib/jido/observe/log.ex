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

  @type level :: Logger.level()

  @doc """
  Returns the current observability log threshold.

  Reads from application config `:jido, :observability, :log_level`.
  Defaults to `:info` if not configured.
  """
  @spec threshold() :: level()
  def threshold do
    Jido.Observe.Config.observe_log_level(nil)
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
    instance = Keyword.get(metadata, :jido_instance)
    threshold = Jido.Observe.Config.observe_log_level(instance)
    Jido.Util.cond_log(threshold, level, message, metadata)
  end
end
