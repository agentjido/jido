defmodule Jido.Telemetry.Config do
  @moduledoc """
  Configuration for Jido's telemetry logging system.

  This module provides functions to check log levels, interestingness thresholds,
  and privacy settings for telemetry events.

  ## Configuration

  All configuration is read from application environment under `:jido, :telemetry`:

      config :jido, :telemetry,
        log_level: :debug,  # :trace | :debug | :info | :warning | :error
        slow_signal_threshold_ms: 10,
        slow_directive_threshold_ms: 5,
        interesting_signal_types: ["jido.strategy.init", "jido.strategy.complete"],
        log_args: :keys_only  # :keys_only | :full | :none

  ## Log Levels

  The telemetry system supports five log levels in order of verbosity:

  - `:trace` - Very verbose, logs every signal and directive
  - `:debug` - Logs interesting events and slow operations
  - `:info` - Logs significant lifecycle events
  - `:warning` - Logs potential issues
  - `:error` - Logs only errors

  ## Examples

      # Check if trace logging is enabled
      if Jido.Telemetry.Config.trace_enabled?() do
        # Log detailed per-signal information
      end

      # Check if an operation is slow
      if duration_ms > Jido.Telemetry.Config.slow_signal_threshold_ms() do
        # Log as interesting even at higher log levels
      end

      # Check argument logging settings
      case Jido.Telemetry.Config.log_args?() do
        :full -> log_full_args(args)
        :keys_only -> log_keys(args)
        :none -> :skip
      end
  """

  @default_log_level :debug
  @default_slow_signal_threshold_ms 10
  @default_slow_directive_threshold_ms 5
  @default_interesting_signal_types [
    "jido.strategy.init",
    "jido.strategy.complete"
  ]
  @default_log_args :keys_only

  @log_level_priority %{
    trace: 0,
    debug: 1,
    info: 2,
    warning: 3,
    error: 4
  }

  # Compile-time defaults for efficiency
  @compile_log_level Application.compile_env(:jido, [:telemetry, :log_level], @default_log_level)

  @doc """
  Returns the current log level.

  ## Examples

      iex> Jido.Telemetry.Config.log_level()
      :debug
  """
  @spec log_level() :: :trace | :debug | :info | :warning | :error
  def log_level do
    get_config(:log_level, @compile_log_level)
  end

  @doc """
  Returns true if trace-level logging is enabled.

  Trace level is the most verbose, logging every signal and directive.

  ## Examples

      iex> Jido.Telemetry.Config.trace_enabled?()
      false
  """
  @spec trace_enabled?() :: boolean()
  def trace_enabled? do
    level_enabled?(:trace)
  end

  @doc """
  Returns true if debug-level logging is enabled.

  ## Examples

      iex> Jido.Telemetry.Config.debug_enabled?()
      true
  """
  @spec debug_enabled?() :: boolean()
  def debug_enabled? do
    level_enabled?(:debug)
  end

  @doc """
  Returns true if the given log level is enabled based on current configuration.

  ## Examples

      iex> Jido.Telemetry.Config.level_enabled?(:debug)
      true

      iex> Jido.Telemetry.Config.level_enabled?(:trace)
      false
  """
  @spec level_enabled?(:trace | :debug | :info | :warning | :error) :: boolean()
  def level_enabled?(level) do
    current = log_level()
    Map.get(@log_level_priority, level, 5) >= Map.get(@log_level_priority, current, 1)
  end

  @doc """
  Returns the slow signal threshold in milliseconds.

  Signals taking longer than this are considered "interesting" and logged at debug level.

  Default: #{@default_slow_signal_threshold_ms}ms

  ## Examples

      iex> Jido.Telemetry.Config.slow_signal_threshold_ms()
      10
  """
  @spec slow_signal_threshold_ms() :: non_neg_integer()
  def slow_signal_threshold_ms do
    get_config(:slow_signal_threshold_ms, @default_slow_signal_threshold_ms)
  end

  @doc """
  Returns the slow directive threshold in milliseconds.

  Directives taking longer than this are considered "interesting" and logged at debug level.

  Default: #{@default_slow_directive_threshold_ms}ms

  ## Examples

      iex> Jido.Telemetry.Config.slow_directive_threshold_ms()
      5
  """
  @spec slow_directive_threshold_ms() :: non_neg_integer()
  def slow_directive_threshold_ms do
    get_config(:slow_directive_threshold_ms, @default_slow_directive_threshold_ms)
  end

  @doc """
  Returns the list of signal types that are always considered "interesting".

  These signals are logged at debug level regardless of duration.

  Default: #{inspect(@default_interesting_signal_types)}

  ## Examples

      iex> "jido.strategy.init" in Jido.Telemetry.Config.interesting_signal_types()
      true
  """
  @spec interesting_signal_types() :: [String.t()]
  def interesting_signal_types do
    get_config(:interesting_signal_types, @default_interesting_signal_types)
  end

  @doc """
  Returns true if the given signal type is considered "interesting".

  ## Examples

      iex> Jido.Telemetry.Config.interesting_signal_type?("jido.strategy.init")
      true

      iex> Jido.Telemetry.Config.interesting_signal_type?("jido.some.random.signal")
      false
  """
  @spec interesting_signal_type?(String.t()) :: boolean()
  def interesting_signal_type?(signal_type) do
    signal_type in interesting_signal_types()
  end

  @doc """
  Returns the action/directive arguments logging mode.

  - `:full` - Log complete arguments
  - `:keys_only` - Log only the keys of arguments (default)
  - `:none` - Do not log arguments

  Default: #{inspect(@default_log_args)}

  ## Examples

      iex> Jido.Telemetry.Config.log_args?()
      :keys_only
  """
  @spec log_args?() :: :keys_only | :full | :none
  def log_args? do
    get_config(:log_args, @default_log_args)
  end

  # Private helpers

  defp get_config(key, default) do
    Application.get_env(:jido, :telemetry, [])
    |> Keyword.get(key, default)
  end
end
