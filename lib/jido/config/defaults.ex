defmodule Jido.Config.Defaults do
  @moduledoc """
  Centralized default values for runtime behavior and observability.

  Keeping defaults in one module avoids drift across API wrappers, runtime
  modules, and configuration resolution.
  """

  @type telemetry_log_level :: :trace | :debug | :info | :warning | :error
  @type telemetry_log_args :: :keys_only | :full | :none
  @type debug_events_mode :: :off | :minimal | :all
  @type tracer_failure_mode :: :warn | :strict

  @jido_shutdown_timeout_ms 10_000

  @telemetry_log_level :info
  @telemetry_log_args :keys_only
  @slow_signal_threshold_ms 10
  @slow_directive_threshold_ms 5
  @interesting_signal_types []
  @observe_log_level :info
  @observe_debug_events :off
  @redact_sensitive false
  @tracer Jido.Observe.NoopTracer
  @tracer_failure_mode :warn
  @debug_max_events 500

  @doc "Default shutdown timeout for the top-level Jido supervisor."
  @spec jido_shutdown_timeout_ms() :: pos_integer()
  def jido_shutdown_timeout_ms, do: @jido_shutdown_timeout_ms

  @doc "Default telemetry log level."
  @spec telemetry_log_level() :: telemetry_log_level()
  def telemetry_log_level, do: @telemetry_log_level

  @doc "Default telemetry argument logging mode."
  @spec telemetry_log_args() :: telemetry_log_args()
  def telemetry_log_args, do: @telemetry_log_args

  @doc "Default slow-signal threshold in milliseconds."
  @spec slow_signal_threshold_ms() :: non_neg_integer()
  def slow_signal_threshold_ms, do: @slow_signal_threshold_ms

  @doc "Default slow-directive threshold in milliseconds."
  @spec slow_directive_threshold_ms() :: non_neg_integer()
  def slow_directive_threshold_ms, do: @slow_directive_threshold_ms

  @doc "Default list of interesting signal types."
  @spec interesting_signal_types() :: [String.t()]
  def interesting_signal_types, do: @interesting_signal_types

  @doc "Default observe log level."
  @spec observe_log_level() :: Logger.level()
  def observe_log_level, do: @observe_log_level

  @doc "Default debug-events mode."
  @spec observe_debug_events() :: debug_events_mode()
  def observe_debug_events, do: @observe_debug_events

  @doc "Default redact-sensitive flag."
  @spec redact_sensitive() :: boolean()
  def redact_sensitive, do: @redact_sensitive

  @doc "Default tracer module."
  @spec tracer() :: module()
  def tracer, do: @tracer

  @doc "Default tracer failure mode."
  @spec tracer_failure_mode() :: tracer_failure_mode()
  def tracer_failure_mode, do: @tracer_failure_mode

  @doc "Default max debug-event buffer size."
  @spec debug_max_events() :: non_neg_integer()
  def debug_max_events, do: @debug_max_events
end
