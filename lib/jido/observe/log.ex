defmodule Jido.Observe.Log do
  @moduledoc """
  Threshold-based observability logging compatibility shim.

  This module preserves the historical public logging API while the runtime
  continues to honor `config :jido, :observability, log_level: ...` and
  per-instance `Jido.Debug` overrides.
  """

  @type level :: Logger.level()

  @doc """
  Returns the current observability log threshold.
  """
  @spec threshold() :: level()
  def threshold do
    Jido.Observe.Config.observe_log_level(nil)
  end

  @doc """
  Conditionally logs a message based on the observability threshold.

  When `:jido_instance` metadata is present, per-instance overrides from
  `Jido.Debug` are honored.
  """
  @spec log(level(), Logger.message(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    instance = Keyword.get(metadata, :jido_instance)
    threshold = Jido.Observe.Config.observe_log_level(instance)
    Jido.Util.cond_log(threshold, level, message, metadata)
  end
end
