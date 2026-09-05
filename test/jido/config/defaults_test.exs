defmodule JidoTest.Config.DefaultsTest do
  use ExUnit.Case, async: true

  alias Jido.Config.Defaults

  test "returns centralized timeout defaults" do
    assert Defaults.jido_shutdown_timeout_ms() == 10_000
  end

  test "returns centralized observability defaults" do
    assert Defaults.telemetry_log_level() == :info
    assert Defaults.telemetry_log_args() == :keys_only
    assert Defaults.slow_signal_threshold_ms() == 10
    assert Defaults.slow_directive_threshold_ms() == 5
    assert Defaults.interesting_signal_types() == []
    assert Defaults.observe_log_level() == :info
    assert Defaults.observe_debug_events() == :off
    refute Defaults.redact_sensitive()
    assert Defaults.tracer() == Jido.Observe.NoopTracer
    assert Defaults.tracer_failure_mode() == :warn
    assert Defaults.debug_max_events() == 500
  end
end
