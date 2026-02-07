defmodule JidoTest.DebugTest do
  use ExUnit.Case, async: false

  alias Jido.Debug

  @test_instance :"jido_debug_test_#{System.unique_integer([:positive])}"

  setup do
    Debug.reset(@test_instance)

    on_exit(fn ->
      Debug.reset(@test_instance)
    end)

    :ok
  end

  describe "enable/3 and level/1" do
    test "default level is :off" do
      assert Debug.level(@test_instance) == :off
    end

    test "enable :on sets level" do
      assert :ok = Debug.enable(@test_instance, :on)
      assert Debug.level(@test_instance) == :on
    end

    test "enable :verbose sets level" do
      assert :ok = Debug.enable(@test_instance, :verbose)
      assert Debug.level(@test_instance) == :verbose
    end

    test "enable :off disables" do
      Debug.enable(@test_instance, :on)
      assert :ok = Debug.enable(@test_instance, :off)
      assert Debug.level(@test_instance) == :off
    end
  end

  describe "enabled?/1" do
    test "false when off" do
      refute Debug.enabled?(@test_instance)
    end

    test "true when on" do
      Debug.enable(@test_instance, :on)
      assert Debug.enabled?(@test_instance)
    end

    test "true when verbose" do
      Debug.enable(@test_instance, :verbose)
      assert Debug.enabled?(@test_instance)
    end
  end

  describe "disable/1" do
    test "disables debug mode" do
      Debug.enable(@test_instance, :on)
      assert :ok = Debug.disable(@test_instance)
      assert Debug.level(@test_instance) == :off
    end

    test "idempotent - can disable when already off" do
      assert :ok = Debug.disable(@test_instance)
    end
  end

  describe "override/2" do
    test "returns nil when debug is off" do
      assert Debug.override(@test_instance, :telemetry_log_level) == nil
    end

    test "returns override when :on" do
      Debug.enable(@test_instance, :on)
      assert Debug.override(@test_instance, :telemetry_log_level) == :debug
      assert Debug.override(@test_instance, :telemetry_log_args) == :keys_only
      assert Debug.override(@test_instance, :observe_log_level) == :debug
      assert Debug.override(@test_instance, :observe_debug_events) == :minimal
    end

    test "returns override when :verbose" do
      Debug.enable(@test_instance, :verbose)
      assert Debug.override(@test_instance, :telemetry_log_level) == :trace
      assert Debug.override(@test_instance, :telemetry_log_args) == :full
      assert Debug.override(@test_instance, :observe_debug_events) == :all
    end

    test "returns nil for unknown override key" do
      Debug.enable(@test_instance, :on)
      assert Debug.override(@test_instance, :nonexistent_key) == nil
    end

    test "redact override when redact: false passed" do
      Debug.enable(@test_instance, :on, redact: false)
      assert Debug.override(@test_instance, :redact_sensitive) == false
    end

    test "no redact override by default" do
      Debug.enable(@test_instance, :on)
      assert Debug.override(@test_instance, :redact_sensitive) == nil
    end
  end

  describe "reset/1" do
    test "resets to :off" do
      Debug.enable(@test_instance, :verbose)
      assert :ok = Debug.reset(@test_instance)
      assert Debug.level(@test_instance) == :off
    end
  end

  describe "status/1" do
    test "returns off status when disabled" do
      status = Debug.status(@test_instance)
      assert status == %{level: :off, overrides: %{}}
    end

    test "returns status map when enabled" do
      Debug.enable(@test_instance, :on)
      status = Debug.status(@test_instance)
      assert status.level == :on
      assert is_map(status.overrides)
      assert status.overrides.telemetry_log_level == :debug
    end
  end

  describe "maybe_enable_from_config/2" do
    test "enables when config has debug: true" do
      Application.put_env(:jido_test, @test_instance, debug: true)

      Debug.maybe_enable_from_config(:jido_test, @test_instance)
      assert Debug.level(@test_instance) == :on

      Application.delete_env(:jido_test, @test_instance)
    end

    test "enables verbose when config has debug: :verbose" do
      Application.put_env(:jido_test, @test_instance, debug: :verbose)

      Debug.maybe_enable_from_config(:jido_test, @test_instance)
      assert Debug.level(@test_instance) == :verbose

      Application.delete_env(:jido_test, @test_instance)
    end

    test "does nothing when no debug config" do
      Application.put_env(:jido_test, @test_instance, [])

      Debug.maybe_enable_from_config(:jido_test, @test_instance)
      assert Debug.level(@test_instance) == :off

      Application.delete_env(:jido_test, @test_instance)
    end
  end

  describe "per-instance isolation" do
    test "debug state is isolated between instances" do
      instance_a = :"jido_debug_test_a_#{System.unique_integer([:positive])}"
      instance_b = :"jido_debug_test_b_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        Debug.reset(instance_a)
        Debug.reset(instance_b)
      end)

      Debug.enable(instance_a, :on)
      Debug.enable(instance_b, :verbose)

      assert Debug.level(instance_a) == :on
      assert Debug.level(instance_b) == :verbose

      Debug.disable(instance_a)
      assert Debug.level(instance_a) == :off
      assert Debug.level(instance_b) == :verbose
    end
  end

  describe "integration with Observe.Config" do
    test "debug override takes priority over global config" do
      Application.put_env(:jido, :telemetry, log_level: :info)

      Debug.enable(@test_instance, :on)

      assert Jido.Observe.Config.telemetry_log_level(@test_instance) == :debug

      assert Jido.Observe.Config.telemetry_log_level(nil) == :info

      Application.delete_env(:jido, :telemetry)
    end

    test "verbose override enables trace" do
      Debug.enable(@test_instance, :verbose)

      assert Jido.Observe.Config.telemetry_log_level(@test_instance) == :trace
      assert Jido.Observe.Config.telemetry_log_args(@test_instance) == :full
      assert Jido.Observe.Config.debug_events(@test_instance) == :all
    end
  end
end
