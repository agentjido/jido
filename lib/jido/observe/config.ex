defmodule Jido.Observe.Config do
  @moduledoc """
  Resolves observability configuration with per-instance support.

  Resolution order (highest priority first):

  1. `Jido.Debug` runtime override (persistent_term, per-instance)
  2. Per-instance app config (`config :my_app, MyApp.Jido, telemetry: [...]`)
  3. Global app config (`config :jido, :telemetry` / `config :jido, :observability`)
  4. Hardcoded default

  When `instance` is `nil`, steps 1-2 are skipped.
  """

  @type instance :: atom() | nil

  # Defaults
  @default_log_level :debug
  @default_log_args :keys_only
  @default_slow_signal_threshold_ms 10
  @default_slow_directive_threshold_ms 5
  @default_interesting_signal_types [
    "jido.strategy.init",
    "jido.strategy.complete"
  ]
  @default_observe_log_level :info
  @default_debug_events :off
  @default_redact_sensitive false
  @default_tracer Jido.Observe.NoopTracer
  @default_debug_max_events 500

  @log_level_priority %{
    trace: 0,
    debug: 1,
    info: 2,
    warning: 3,
    error: 4
  }

  # --- Telemetry settings ---

  @doc "Returns the telemetry log level for the given instance."
  @spec telemetry_log_level(instance()) :: :trace | :debug | :info | :warning | :error
  def telemetry_log_level(instance \\ nil)
  def telemetry_log_level(nil), do: global_telemetry(:log_level, @default_log_level)

  def telemetry_log_level(instance) do
    with nil <- Jido.Debug.override(instance, :telemetry_log_level),
         nil <- instance_telemetry(instance, :log_level) do
      global_telemetry(:log_level, @default_log_level)
    end
  end

  @doc "Returns the argument logging mode for the given instance."
  @spec telemetry_log_args(instance()) :: :keys_only | :full | :none
  def telemetry_log_args(instance \\ nil)
  def telemetry_log_args(nil), do: global_telemetry(:log_args, @default_log_args)

  def telemetry_log_args(instance) do
    with nil <- Jido.Debug.override(instance, :telemetry_log_args),
         nil <- instance_telemetry(instance, :log_args) do
      global_telemetry(:log_args, @default_log_args)
    end
  end

  @doc "Returns the slow signal threshold in milliseconds."
  @spec slow_signal_threshold_ms(instance()) :: non_neg_integer()
  def slow_signal_threshold_ms(instance \\ nil)

  def slow_signal_threshold_ms(nil),
    do: global_telemetry(:slow_signal_threshold_ms, @default_slow_signal_threshold_ms)

  def slow_signal_threshold_ms(instance) do
    with nil <- Jido.Debug.override(instance, :slow_signal_threshold_ms),
         nil <- instance_telemetry(instance, :slow_signal_threshold_ms) do
      global_telemetry(:slow_signal_threshold_ms, @default_slow_signal_threshold_ms)
    end
  end

  @doc "Returns the slow directive threshold in milliseconds."
  @spec slow_directive_threshold_ms(instance()) :: non_neg_integer()
  def slow_directive_threshold_ms(instance \\ nil)

  def slow_directive_threshold_ms(nil),
    do: global_telemetry(:slow_directive_threshold_ms, @default_slow_directive_threshold_ms)

  def slow_directive_threshold_ms(instance) do
    with nil <- Jido.Debug.override(instance, :slow_directive_threshold_ms),
         nil <- instance_telemetry(instance, :slow_directive_threshold_ms) do
      global_telemetry(:slow_directive_threshold_ms, @default_slow_directive_threshold_ms)
    end
  end

  @doc "Returns the list of signal types considered interesting."
  @spec interesting_signal_types(instance()) :: [String.t()]
  def interesting_signal_types(instance \\ nil)

  def interesting_signal_types(nil),
    do: global_telemetry(:interesting_signal_types, @default_interesting_signal_types)

  def interesting_signal_types(instance) do
    with nil <- Jido.Debug.override(instance, :interesting_signal_types),
         nil <- instance_telemetry(instance, :interesting_signal_types) do
      global_telemetry(:interesting_signal_types, @default_interesting_signal_types)
    end
  end

  @doc "Returns true if trace-level logging is enabled."
  @spec trace_enabled?(instance()) :: boolean()
  def trace_enabled?(instance \\ nil) do
    telemetry_log_level(instance) == :trace
  end

  @doc "Returns true if debug-level logging is enabled."
  @spec debug_enabled?(instance()) :: boolean()
  def debug_enabled?(instance \\ nil) do
    level = telemetry_log_level(instance)
    Map.get(@log_level_priority, level, 5) <= Map.get(@log_level_priority, :debug, 1)
  end

  @doc "Returns true if the given log level is enabled."
  @spec level_enabled?(instance(), atom()) :: boolean()
  def level_enabled?(instance \\ nil, level) do
    current = telemetry_log_level(instance)
    Map.get(@log_level_priority, level, 5) >= Map.get(@log_level_priority, current, 1)
  end

  @doc "Returns true if the signal type is considered interesting."
  @spec interesting_signal_type?(instance(), String.t()) :: boolean()
  def interesting_signal_type?(instance \\ nil, signal_type) do
    signal_type in interesting_signal_types(instance)
  end

  # --- Observe settings ---

  @doc "Returns the observability log level for the given instance."
  @spec observe_log_level(instance()) :: Logger.level()
  def observe_log_level(instance \\ nil)
  def observe_log_level(nil), do: global_observability(:log_level, @default_observe_log_level)

  def observe_log_level(instance) do
    with nil <- Jido.Debug.override(instance, :observe_log_level),
         nil <- instance_observability(instance, :log_level) do
      global_observability(:log_level, @default_observe_log_level)
    end
  end

  @doc "Returns the debug events mode for the given instance."
  @spec debug_events(instance()) :: :off | :minimal | :all
  def debug_events(instance \\ nil)
  def debug_events(nil), do: global_observability(:debug_events, @default_debug_events)

  def debug_events(instance) do
    with nil <- Jido.Debug.override(instance, :observe_debug_events),
         nil <- instance_observability(instance, :debug_events) do
      global_observability(:debug_events, @default_debug_events)
    end
  end

  @doc "Returns true if debug events are enabled."
  @spec debug_events_enabled?(instance()) :: boolean()
  def debug_events_enabled?(instance \\ nil) do
    debug_events(instance) != :off
  end

  @doc "Returns true if sensitive data should be redacted."
  @spec redact_sensitive?(instance()) :: boolean()
  def redact_sensitive?(instance \\ nil)

  def redact_sensitive?(nil),
    do: global_observability(:redact_sensitive, @default_redact_sensitive) == true

  def redact_sensitive?(instance) do
    case Jido.Debug.override(instance, :redact_sensitive) do
      nil ->
        case instance_observability(instance, :redact_sensitive) do
          nil -> global_observability(:redact_sensitive, @default_redact_sensitive) == true
          val -> val == true
        end

      val ->
        val == true
    end
  end

  @doc "Returns the tracer module for the given instance."
  @spec tracer(instance()) :: module()
  def tracer(instance \\ nil)
  def tracer(nil), do: global_observability(:tracer, @default_tracer)

  def tracer(instance) do
    with nil <- Jido.Debug.override(instance, :tracer),
         nil <- instance_observability(instance, :tracer) do
      global_observability(:tracer, @default_tracer)
    end
  end

  # --- Debug buffer settings ---

  @doc "Returns the maximum number of debug events to store."
  @spec debug_max_events(instance()) :: non_neg_integer()
  def debug_max_events(instance \\ nil)
  def debug_max_events(nil), do: global_telemetry(:debug_max_events, @default_debug_max_events)

  def debug_max_events(instance) do
    with nil <- Jido.Debug.override(instance, :debug_max_events),
         nil <- instance_telemetry(instance, :debug_max_events) do
      global_telemetry(:debug_max_events, @default_debug_max_events)
    end
  end

  # --- Private helpers ---

  defp instance_telemetry(instance, key) do
    otp_app = instance_otp_app(instance)

    if otp_app do
      otp_app
      |> Application.get_env(instance, [])
      |> Keyword.get(:telemetry, [])
      |> Keyword.get(key)
    end
  end

  defp instance_observability(instance, key) do
    otp_app = instance_otp_app(instance)

    if otp_app do
      otp_app
      |> Application.get_env(instance, [])
      |> Keyword.get(:observability, [])
      |> Keyword.get(key)
    end
  end

  defp instance_otp_app(instance) when is_atom(instance) do
    case function_exported?(instance, :__otp_app__, 0) do
      true -> instance.__otp_app__()
      false -> nil
    end
  end

  defp global_telemetry(key, default) do
    :jido |> Application.get_env(:telemetry, []) |> Keyword.get(key, default)
  end

  defp global_observability(key, default) do
    :jido |> Application.get_env(:observability, []) |> Keyword.get(key, default)
  end
end
