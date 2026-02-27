defmodule JidoTest.Observe.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Config.Defaults
  alias Jido.Observe.Config

  defmodule ValidTracer do
    @moduledoc false
    @behaviour Jido.Observe.Tracer

    @impl true
    def span_start(_event_prefix, _metadata), do: :ok

    @impl true
    def span_stop(_ctx, _measurements), do: :ok

    @impl true
    def span_exception(_ctx, _kind, _reason, _stacktrace), do: :ok
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:jido, :telemetry)
      Application.delete_env(:jido, :observability)
    end)

    :ok
  end

  describe "telemetry_log_level/1" do
    test "returns default when no config set" do
      assert Config.telemetry_log_level(nil) == Defaults.telemetry_log_level()
    end

    test "reads from global config" do
      Application.put_env(:jido, :telemetry, log_level: :info)
      assert Config.telemetry_log_level(nil) == :info
    end

    test "falls back to default when global value is invalid" do
      Application.put_env(:jido, :telemetry, log_level: :invalid)
      assert Config.telemetry_log_level(nil) == Defaults.telemetry_log_level()
    end

    test "nil instance skips debug override" do
      assert Config.telemetry_log_level(nil) == Defaults.telemetry_log_level()
    end
  end

  describe "telemetry_log_args/1" do
    test "returns default when no config set" do
      assert Config.telemetry_log_args(nil) == Defaults.telemetry_log_args()
    end

    test "reads from global config" do
      Application.put_env(:jido, :telemetry, log_args: :full)
      assert Config.telemetry_log_args(nil) == :full
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :telemetry, log_args: :verbose)
      assert Config.telemetry_log_args(nil) == Defaults.telemetry_log_args()
    end
  end

  describe "slow_signal_threshold_ms/1" do
    test "returns default" do
      assert Config.slow_signal_threshold_ms(nil) == Defaults.slow_signal_threshold_ms()
    end

    test "reads from global config" do
      Application.put_env(:jido, :telemetry, slow_signal_threshold_ms: 50)
      assert Config.slow_signal_threshold_ms(nil) == 50
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :telemetry, slow_signal_threshold_ms: -5)
      assert Config.slow_signal_threshold_ms(nil) == Defaults.slow_signal_threshold_ms()
    end
  end

  describe "slow_directive_threshold_ms/1" do
    test "returns default" do
      assert Config.slow_directive_threshold_ms(nil) == Defaults.slow_directive_threshold_ms()
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :telemetry, slow_directive_threshold_ms: "slow")
      assert Config.slow_directive_threshold_ms(nil) == Defaults.slow_directive_threshold_ms()
    end
  end

  describe "interesting_signal_types/1" do
    test "returns default list" do
      types = Config.interesting_signal_types(nil)
      assert is_list(types)
      assert "jido.strategy.init" in types
    end

    test "falls back to defaults when list contains non-strings" do
      Application.put_env(:jido, :telemetry, interesting_signal_types: ["ok", 123])
      assert Config.interesting_signal_types(nil) == Defaults.interesting_signal_types()
    end
  end

  describe "trace_enabled?/1" do
    test "false by default" do
      refute Config.trace_enabled?(nil)
    end

    test "true when log level is trace" do
      Application.put_env(:jido, :telemetry, log_level: :trace)
      assert Config.trace_enabled?(nil)
    end
  end

  describe "debug_enabled?/1" do
    test "true by default (default log level is :debug)" do
      assert Config.debug_enabled?(nil)
    end

    test "false when log level is info" do
      Application.put_env(:jido, :telemetry, log_level: :info)
      refute Config.debug_enabled?(nil)
    end
  end

  describe "observe_log_level/1" do
    test "returns default" do
      assert Config.observe_log_level(nil) == Defaults.observe_log_level()
    end

    test "reads from global observability config" do
      Application.put_env(:jido, :observability, log_level: :debug)
      assert Config.observe_log_level(nil) == :debug
    end

    test "falls back to default for invalid logger level" do
      Application.put_env(:jido, :observability, log_level: :invalid)
      assert Config.observe_log_level(nil) == Defaults.observe_log_level()
    end
  end

  describe "debug_events/1" do
    test "returns :off by default" do
      assert Config.debug_events(nil) == Defaults.observe_debug_events()
    end

    test "reads from global observability config" do
      Application.put_env(:jido, :observability, debug_events: :all)
      assert Config.debug_events(nil) == :all
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :observability, debug_events: :everything)
      assert Config.debug_events(nil) == Defaults.observe_debug_events()
    end
  end

  describe "debug_events_enabled?/1" do
    test "false by default" do
      refute Config.debug_events_enabled?(nil)
    end

    test "true when debug_events is :all" do
      Application.put_env(:jido, :observability, debug_events: :all)
      assert Config.debug_events_enabled?(nil)
    end

    test "true when debug_events is :minimal" do
      Application.put_env(:jido, :observability, debug_events: :minimal)
      assert Config.debug_events_enabled?(nil)
    end
  end

  describe "redact_sensitive?/1" do
    test "false by default" do
      refute Config.redact_sensitive?(nil)
    end

    test "reads from global observability config" do
      Application.put_env(:jido, :observability, redact_sensitive: true)
      assert Config.redact_sensitive?(nil)
    end
  end

  describe "tracer/1" do
    test "returns NoopTracer by default" do
      assert Config.tracer(nil) == Jido.Observe.NoopTracer
    end

    test "returns configured tracer when it implements the contract" do
      Application.put_env(:jido, :observability, tracer: ValidTracer)
      assert Config.tracer(nil) == ValidTracer
    end

    test "falls back to default tracer when configured module is invalid" do
      Application.put_env(:jido, :observability, tracer: Date)
      assert Config.tracer(nil) == Defaults.tracer()
    end
  end

  describe "tracer_failure_mode/1" do
    test "returns :warn by default" do
      assert Config.tracer_failure_mode(nil) == :warn
    end

    test "reads from global observability config" do
      Application.put_env(:jido, :observability, tracer_failure_mode: :strict)
      assert Config.tracer_failure_mode(nil) == :strict
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :observability, tracer_failure_mode: :invalid)
      assert Config.tracer_failure_mode(nil) == :warn
    end
  end

  describe "debug_max_events/1" do
    test "returns default by default" do
      assert Config.debug_max_events(nil) == Defaults.debug_max_events()
    end

    test "reads from global telemetry config" do
      Application.put_env(:jido, :telemetry, debug_max_events: 1000)
      assert Config.debug_max_events(nil) == 1000
    end

    test "falls back to default when value is invalid" do
      Application.put_env(:jido, :telemetry, debug_max_events: -1)
      assert Config.debug_max_events(nil) == Defaults.debug_max_events()
    end
  end

  describe "level_enabled?/2" do
    test "debug is enabled at debug level" do
      assert Config.level_enabled?(nil, :debug)
    end

    test "trace is not enabled at debug level" do
      refute Config.level_enabled?(nil, :trace)
    end

    test "info is enabled at debug level" do
      assert Config.level_enabled?(nil, :info)
    end
  end

  describe "interesting_signal_type?/2" do
    test "returns true for configured types" do
      assert Config.interesting_signal_type?(nil, "jido.strategy.init")
    end

    test "returns false for unknown types" do
      refute Config.interesting_signal_type?(nil, "some.random.signal")
    end
  end
end
