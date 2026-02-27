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

  @agent_server_shutdown_timeout_ms 5_000
  @agent_server_call_timeout_ms 5_000
  @agent_server_await_timeout_ms 10_000

  @await_timeout_ms 10_000
  @await_child_timeout_ms 30_000

  @worker_pool_checkout_timeout_ms 5_000
  @worker_pool_call_timeout_ms 5_000

  @instance_manager_stop_timeout_ms 5_000

  @telemetry_log_level :debug
  @telemetry_log_args :keys_only
  @slow_signal_threshold_ms 10
  @slow_directive_threshold_ms 5
  @interesting_signal_types [
    "jido.strategy.init",
    "jido.strategy.complete"
  ]
  @observe_log_level :info
  @observe_debug_events :off
  @redact_sensitive false
  @tracer Jido.Observe.NoopTracer
  @tracer_failure_mode :warn
  @debug_max_events 500

  @doc "Default shutdown timeout for the top-level Jido supervisor."
  @spec jido_shutdown_timeout_ms() :: pos_integer()
  def jido_shutdown_timeout_ms, do: @jido_shutdown_timeout_ms

  @doc "Default shutdown timeout for AgentServer workers."
  @spec agent_server_shutdown_timeout_ms() :: pos_integer()
  def agent_server_shutdown_timeout_ms, do: @agent_server_shutdown_timeout_ms

  @doc "Default timeout for synchronous AgentServer calls."
  @spec agent_server_call_timeout_ms() :: pos_integer()
  def agent_server_call_timeout_ms, do: @agent_server_call_timeout_ms

  @doc "Default timeout for AgentServer.await_completion/2."
  @spec agent_server_await_timeout_ms() :: pos_integer()
  def agent_server_await_timeout_ms, do: @agent_server_await_timeout_ms

  @doc "Default timeout for Jido.Await helpers."
  @spec await_timeout_ms() :: pos_integer()
  def await_timeout_ms, do: @await_timeout_ms

  @doc "Default timeout for Jido.await_child/4."
  @spec await_child_timeout_ms() :: pos_integer()
  def await_child_timeout_ms, do: @await_child_timeout_ms

  @doc "Default checkout timeout for worker pools."
  @spec worker_pool_checkout_timeout_ms() :: pos_integer()
  def worker_pool_checkout_timeout_ms, do: @worker_pool_checkout_timeout_ms

  @doc "Default call timeout when signaling pooled agents."
  @spec worker_pool_call_timeout_ms() :: pos_integer()
  def worker_pool_call_timeout_ms, do: @worker_pool_call_timeout_ms

  @doc "Default graceful-stop timeout for instance-managed agents."
  @spec instance_manager_stop_timeout_ms() :: pos_integer()
  def instance_manager_stop_timeout_ms, do: @instance_manager_stop_timeout_ms

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
