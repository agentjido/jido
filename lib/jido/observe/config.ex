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

  alias Jido.Config.Defaults

  @type instance :: atom() | nil

  @log_level_priority %{
    trace: 0,
    debug: 1,
    info: 2,
    warning: 3,
    error: 4
  }

  @telemetry_log_levels [:trace, :debug, :info, :warning, :error]
  @telemetry_log_args_modes [:keys_only, :full, :none]
  @debug_events_modes [:off, :minimal, :all]
  @observe_log_levels Logger.levels()

  # --- Telemetry settings ---

  @doc "Returns the telemetry log level for the given instance."
  @spec telemetry_log_level(instance()) :: :trace | :debug | :info | :warning | :error
  def telemetry_log_level(instance \\ nil)

  def telemetry_log_level(nil) do
    global_telemetry(:log_level, Defaults.telemetry_log_level())
    |> normalize_telemetry_log_level()
  end

  def telemetry_log_level(instance) do
    with nil <- Jido.Debug.override(instance, :telemetry_log_level),
         nil <- instance_telemetry(instance, :log_level) do
      global_telemetry(:log_level, Defaults.telemetry_log_level())
    end
    |> normalize_telemetry_log_level()
  end

  @doc "Returns the argument logging mode for the given instance."
  @spec telemetry_log_args(instance()) :: :keys_only | :full | :none
  def telemetry_log_args(instance \\ nil)

  def telemetry_log_args(nil) do
    global_telemetry(:log_args, Defaults.telemetry_log_args())
    |> normalize_telemetry_log_args()
  end

  def telemetry_log_args(instance) do
    with nil <- Jido.Debug.override(instance, :telemetry_log_args),
         nil <- instance_telemetry(instance, :log_args) do
      global_telemetry(:log_args, Defaults.telemetry_log_args())
    end
    |> normalize_telemetry_log_args()
  end

  @doc "Returns the slow signal threshold in milliseconds."
  @spec slow_signal_threshold_ms(instance()) :: non_neg_integer()
  def slow_signal_threshold_ms(instance \\ nil)

  def slow_signal_threshold_ms(nil),
    do:
      global_telemetry(:slow_signal_threshold_ms, Defaults.slow_signal_threshold_ms())
      |> normalize_non_neg_integer(Defaults.slow_signal_threshold_ms())

  def slow_signal_threshold_ms(instance) do
    with nil <- Jido.Debug.override(instance, :slow_signal_threshold_ms),
         nil <- instance_telemetry(instance, :slow_signal_threshold_ms) do
      global_telemetry(:slow_signal_threshold_ms, Defaults.slow_signal_threshold_ms())
    end
    |> normalize_non_neg_integer(Defaults.slow_signal_threshold_ms())
  end

  @doc "Returns the slow directive threshold in milliseconds."
  @spec slow_directive_threshold_ms(instance()) :: non_neg_integer()
  def slow_directive_threshold_ms(instance \\ nil)

  def slow_directive_threshold_ms(nil),
    do:
      global_telemetry(:slow_directive_threshold_ms, Defaults.slow_directive_threshold_ms())
      |> normalize_non_neg_integer(Defaults.slow_directive_threshold_ms())

  def slow_directive_threshold_ms(instance) do
    with nil <- Jido.Debug.override(instance, :slow_directive_threshold_ms),
         nil <- instance_telemetry(instance, :slow_directive_threshold_ms) do
      global_telemetry(:slow_directive_threshold_ms, Defaults.slow_directive_threshold_ms())
    end
    |> normalize_non_neg_integer(Defaults.slow_directive_threshold_ms())
  end

  @doc "Returns the list of signal types considered interesting."
  @spec interesting_signal_types(instance()) :: [String.t()]
  def interesting_signal_types(instance \\ nil)

  def interesting_signal_types(nil),
    do:
      global_telemetry(:interesting_signal_types, Defaults.interesting_signal_types())
      |> normalize_interesting_signal_types()

  def interesting_signal_types(instance) do
    with nil <- Jido.Debug.override(instance, :interesting_signal_types),
         nil <- instance_telemetry(instance, :interesting_signal_types) do
      global_telemetry(:interesting_signal_types, Defaults.interesting_signal_types())
    end
    |> normalize_interesting_signal_types()
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

  def observe_log_level(nil) do
    global_observability(:log_level, Defaults.observe_log_level())
    |> normalize_observe_log_level()
  end

  def observe_log_level(instance) do
    with nil <- Jido.Debug.override(instance, :observe_log_level),
         nil <- instance_observability(instance, :log_level) do
      global_observability(:log_level, Defaults.observe_log_level())
    end
    |> normalize_observe_log_level()
  end

  @doc "Returns the debug events mode for the given instance."
  @spec debug_events(instance()) :: :off | :minimal | :all
  def debug_events(instance \\ nil)

  def debug_events(nil) do
    global_observability(:debug_events, Defaults.observe_debug_events())
    |> normalize_debug_events()
  end

  def debug_events(instance) do
    with nil <- Jido.Debug.override(instance, :observe_debug_events),
         nil <- instance_observability(instance, :debug_events) do
      global_observability(:debug_events, Defaults.observe_debug_events())
    end
    |> normalize_debug_events()
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
    do:
      global_observability(:redact_sensitive, Defaults.redact_sensitive())
      |> normalize_boolean()

  def redact_sensitive?(instance) do
    with nil <- Jido.Debug.override(instance, :redact_sensitive),
         nil <- instance_observability(instance, :redact_sensitive) do
      global_observability(:redact_sensitive, Defaults.redact_sensitive())
    end
    |> normalize_boolean()
  end

  @doc "Returns the tracer module for the given instance."
  @spec tracer(instance()) :: module()
  def tracer(instance \\ nil)

  def tracer(nil) do
    global_observability(:tracer, Defaults.tracer())
    |> normalize_tracer()
  end

  def tracer(instance) do
    with nil <- Jido.Debug.override(instance, :tracer),
         nil <- instance_observability(instance, :tracer) do
      global_observability(:tracer, Defaults.tracer())
    end
    |> normalize_tracer()
  end

  # --- Debug buffer settings ---

  @doc "Returns the maximum number of debug events to store."
  @spec debug_max_events(instance()) :: non_neg_integer()
  def debug_max_events(instance \\ nil)

  def debug_max_events(nil) do
    global_telemetry(:debug_max_events, Defaults.debug_max_events())
    |> normalize_non_neg_integer(Defaults.debug_max_events())
  end

  def debug_max_events(instance) do
    with nil <- Jido.Debug.override(instance, :debug_max_events),
         nil <- instance_telemetry(instance, :debug_max_events) do
      global_telemetry(:debug_max_events, Defaults.debug_max_events())
    end
    |> normalize_non_neg_integer(Defaults.debug_max_events())
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

  defp normalize_telemetry_log_level(level) when level in @telemetry_log_levels, do: level
  defp normalize_telemetry_log_level(_), do: Defaults.telemetry_log_level()

  defp normalize_telemetry_log_args(mode) when mode in @telemetry_log_args_modes, do: mode
  defp normalize_telemetry_log_args(_), do: Defaults.telemetry_log_args()

  defp normalize_observe_log_level(level) when level in @observe_log_levels, do: level
  defp normalize_observe_log_level(_), do: Defaults.observe_log_level()

  defp normalize_debug_events(mode) when mode in @debug_events_modes, do: mode
  defp normalize_debug_events(_), do: Defaults.observe_debug_events()

  defp normalize_interesting_signal_types(types) when is_list(types) do
    if Enum.all?(types, &is_binary/1), do: types, else: Defaults.interesting_signal_types()
  end

  defp normalize_interesting_signal_types(_), do: Defaults.interesting_signal_types()

  defp normalize_non_neg_integer(value, _default) when is_integer(value) and value >= 0, do: value
  defp normalize_non_neg_integer(_, default), do: default

  defp normalize_boolean(true), do: true
  defp normalize_boolean(_), do: false

  defp normalize_tracer(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :span_start, 2) and
             function_exported?(module, :span_stop, 2) and
             function_exported?(module, :span_exception, 4) do
          module
        else
          Defaults.tracer()
        end

      _ ->
        Defaults.tracer()
    end
  end

  defp normalize_tracer(_), do: Defaults.tracer()
end
