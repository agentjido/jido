defmodule Jido.Telemetry.Config do
  @moduledoc """
  Deprecated. Use `Jido.Observe.Config` instead.

  This module is maintained for backward compatibility. All functions
  delegate to `Jido.Observe.Config` with `nil` instance (global config).
  """

  @deprecated "Use Jido.Observe.Config.telemetry_log_level/1 instead"
  @spec log_level() :: :trace | :debug | :info | :warning | :error
  def log_level do
    Jido.Observe.Config.telemetry_log_level(nil)
  end

  @deprecated "Use Jido.Observe.Config.trace_enabled?/1 instead"
  @spec trace_enabled?() :: boolean()
  def trace_enabled? do
    Jido.Observe.Config.trace_enabled?(nil)
  end

  @deprecated "Use Jido.Observe.Config.debug_enabled?/1 instead"
  @spec debug_enabled?() :: boolean()
  def debug_enabled? do
    Jido.Observe.Config.debug_enabled?(nil)
  end

  @deprecated "Use Jido.Observe.Config.level_enabled?/2 instead"
  @spec level_enabled?(:trace | :debug | :info | :warning | :error) :: boolean()
  def level_enabled?(level) do
    Jido.Observe.Config.level_enabled?(nil, level)
  end

  @deprecated "Use Jido.Observe.Config.slow_signal_threshold_ms/1 instead"
  @spec slow_signal_threshold_ms() :: non_neg_integer()
  def slow_signal_threshold_ms do
    Jido.Observe.Config.slow_signal_threshold_ms(nil)
  end

  @deprecated "Use Jido.Observe.Config.slow_directive_threshold_ms/1 instead"
  @spec slow_directive_threshold_ms() :: non_neg_integer()
  def slow_directive_threshold_ms do
    Jido.Observe.Config.slow_directive_threshold_ms(nil)
  end

  @deprecated "Use Jido.Observe.Config.interesting_signal_types/1 instead"
  @spec interesting_signal_types() :: [String.t()]
  def interesting_signal_types do
    Jido.Observe.Config.interesting_signal_types(nil)
  end

  @deprecated "Use Jido.Observe.Config.interesting_signal_type?/2 instead"
  @spec interesting_signal_type?(String.t()) :: boolean()
  def interesting_signal_type?(signal_type) do
    Jido.Observe.Config.interesting_signal_type?(nil, signal_type)
  end

  @deprecated "Use Jido.Observe.Config.telemetry_log_args/1 instead"
  @spec log_args?() :: :keys_only | :full | :none
  def log_args? do
    Jido.Observe.Config.telemetry_log_args(nil)
  end
end
