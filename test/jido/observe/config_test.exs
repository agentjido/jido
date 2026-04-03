defmodule JidoTest.Observe.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Config.Defaults
  alias Jido.Debug
  alias Jido.Observe.Config

  @test_instance :"jido_observe_config_#{System.unique_integer([:positive])}"

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
    Debug.reset(@test_instance)

    on_exit(fn ->
      Application.delete_env(:jido, :telemetry)
      Application.delete_env(:jido, :observability)
      Debug.reset(@test_instance)
    end)

    :ok
  end

  describe "telemetry_log_level/1" do
    test "returns default when no config set" do
      assert Config.telemetry_log_level(nil) == Defaults.telemetry_log_level()
    end

    test "reads from global config" do
      Application.put_env(:jido, :telemetry, log_level: :warning)
      assert Config.telemetry_log_level(nil) == :warning
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
    test "false by default (default log level is :warning)" do
      refute Config.debug_enabled?(nil)
    end

    test "false when log level is warning" do
      Application.put_env(:jido, :telemetry, log_level: :warning)
      refute Config.debug_enabled?(nil)
    end
  end

  describe "action_log_level/1" do
    test "suppresses verbose action logs when args are keys_only" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :keys_only)

      assert Config.action_log_level(nil) == :warning
    end

    test "enables full action logs only when args are full" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :full)

      assert Config.action_log_level(nil) == :debug
    end

    test "maps trace telemetry to debug for action logger" do
      Application.put_env(:jido, :telemetry, log_level: :trace, log_args: :full)

      assert Config.action_log_level(nil) == :debug
    end

    test "honors debug override for keys_only mode" do
      Application.put_env(:jido, :telemetry, log_level: :trace, log_args: :full)
      Debug.enable(@test_instance, :on)

      assert Config.action_log_level(@test_instance) == :warning
    end

    test "honors verbose debug override for full args" do
      Application.put_env(:jido, :telemetry, log_level: :warning, log_args: :none)
      Debug.enable(@test_instance, :verbose)

      assert Config.action_log_level(@test_instance) == :debug
    end
  end

  describe "action_telemetry_mode/1" do
    test "suppresses action telemetry when args are keys_only" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :keys_only)

      assert Config.action_telemetry_mode(nil) == :silent
    end

    test "suppresses action telemetry when args are none" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :none)

      assert Config.action_telemetry_mode(nil) == :silent
    end

    test "enables action telemetry only when args are full" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :full)

      assert Config.action_telemetry_mode(nil) == :full
    end

    test "honors verbose debug override for full action telemetry" do
      Application.put_env(:jido, :telemetry, log_level: :warning, log_args: :none)
      Debug.enable(@test_instance, :verbose)

      assert Config.action_telemetry_mode(@test_instance) == :full
    end
  end

  describe "action_exec_opts/2" do
    test "adds derived exec options without overwriting explicit opts" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :keys_only)

      opts = Config.action_exec_opts(nil, timeout: 10)

      assert Keyword.get(opts, :log_level) == :warning
      assert Keyword.get(opts, :telemetry) == :silent
      assert Keyword.get(opts, :timeout) == 10

      explicit_opts =
        Config.action_exec_opts(nil, log_level: :error, telemetry: :full, timeout: 10)

      assert Keyword.get(explicit_opts, :log_level) == :error
      assert Keyword.get(explicit_opts, :telemetry) == :full
      assert Keyword.get(explicit_opts, :timeout) == 10
    end

    test "strips internal Jido instance plumbing before calling Jido.Exec" do
      Application.put_env(:jido, :telemetry, log_level: :debug, log_args: :keys_only)

      opts = Config.action_exec_opts(nil, __jido_instance__: Jido, timeout: 10)

      refute Keyword.has_key?(opts, :__jido_instance__)
      assert Keyword.get(opts, :log_level) == :warning
      assert Keyword.get(opts, :telemetry) == :silent
      assert Keyword.get(opts, :timeout) == 10
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
    test "debug is not enabled at warning level" do
      refute Config.level_enabled?(nil, :debug)
    end

    test "trace is not enabled at warning level" do
      refute Config.level_enabled?(nil, :trace)
    end

    test "warning is enabled at the default warning level" do
      assert Config.level_enabled?(nil, :warning)
    end

    test "info is enabled when configured log level is info" do
      Application.put_env(:jido, :telemetry, log_level: :info)
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
