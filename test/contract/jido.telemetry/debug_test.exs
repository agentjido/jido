defmodule JidoTest.TelemetryDebugTest do
  use Covenant.Case, component: "jido.telemetry", async: false

  @moduletag obligation: "jido.telemetry.I4"

  alias Jido.Telemetry

  @test_instance :"jido_debug_test_#{System.unique_integer([:positive])}"

  setup do
    instance_config = Application.fetch_env(:jido_test, @test_instance)
    telemetry = Application.fetch_env(:jido, :telemetry)

    on_exit(fn ->
      restore_env(:jido_test, @test_instance, instance_config)
      restore_env(:jido, :telemetry, telemetry)
      Telemetry.set_debug(@test_instance, :off)
    end)

    Application.delete_env(:jido_test, @test_instance)
    Application.delete_env(:jido, :telemetry)
    Telemetry.set_debug(@test_instance, :off)

    :ok
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)

  describe "set_debug/2 and debug_level/1" do
    test "default level is :off" do
      assert Telemetry.debug_level(@test_instance) == :off
    end

    test "setting :on sets level" do
      assert :ok = Telemetry.set_debug(@test_instance, :on)
      assert Telemetry.debug_level(@test_instance) == :on
    end

    test "setting :verbose sets level" do
      assert :ok = Telemetry.set_debug(@test_instance, :verbose)
      assert Telemetry.debug_level(@test_instance) == :verbose
    end

    test "setting :off disables" do
      Telemetry.set_debug(@test_instance, :on)
      assert :ok = Telemetry.set_debug(@test_instance, :off)
      assert Telemetry.debug_level(@test_instance) == :off
    end

    test "rejects an unsupported level" do
      assert_raise FunctionClauseError, fn ->
        apply(Telemetry, :set_debug, [@test_instance, :invalid])
      end

      assert Telemetry.debug_level(@test_instance) == :off
    end
  end

  describe "enabled state" do
    test "false when off" do
      assert Telemetry.debug_level(@test_instance) == :off
    end

    test "true when on" do
      Telemetry.set_debug(@test_instance, :on)
      assert Telemetry.debug_level(@test_instance) != :off
    end

    test "true when verbose" do
      Telemetry.set_debug(@test_instance, :verbose)
      assert Telemetry.debug_level(@test_instance) != :off
    end
  end

  describe "disable through set_debug/2" do
    test "disables debug mode" do
      Telemetry.set_debug(@test_instance, :on)
      assert :ok = Telemetry.set_debug(@test_instance, :off)
      assert Telemetry.debug_level(@test_instance) == :off
    end

    test "idempotent - can disable when already off" do
      assert :ok = Telemetry.set_debug(@test_instance, :off)
    end
  end

  describe "debug_status/1 overrides" do
    test "returns nil when debug is off" do
      assert Map.get(Telemetry.debug_status(@test_instance).overrides, :semantic_log_mode) == nil
    end

    test "returns override when :on" do
      Telemetry.set_debug(@test_instance, :on)
      assert Telemetry.debug_status(@test_instance).overrides.semantic_log_mode == :interesting
    end

    test "returns override when :verbose" do
      Telemetry.set_debug(@test_instance, :verbose)
      assert Telemetry.debug_status(@test_instance).overrides.semantic_log_mode == :all
    end

    test "returns nil for unknown override key" do
      Telemetry.set_debug(@test_instance, :on)
      assert Map.get(Telemetry.debug_status(@test_instance).overrides, :nonexistent_key) == nil
    end
  end

  describe "reset through set_debug/2" do
    test "resets to :off" do
      Telemetry.set_debug(@test_instance, :verbose)
      assert :ok = Telemetry.set_debug(@test_instance, :off)
      assert Telemetry.debug_level(@test_instance) == :off
    end
  end

  describe "debug_status/1" do
    test "returns off status when disabled" do
      status = Telemetry.debug_status(@test_instance)
      assert status == %{level: :off, overrides: %{}}
    end

    test "returns status map when enabled" do
      Telemetry.set_debug(@test_instance, :on)
      status = Telemetry.debug_status(@test_instance)
      assert status.level == :on
      assert is_map(status.overrides)
      assert status.overrides.semantic_log_mode == :interesting
    end

    test "malformed runtime state uses the disabled defaults" do
      for state <- [:invalid, %{}, %{level: :invalid}, %{level: :on, overrides: :invalid}] do
        :persistent_term.put({:jido_debug, @test_instance}, state)

        assert Telemetry.debug_level(@test_instance) == :off
        assert Telemetry.debug_status(@test_instance) == %{level: :off, overrides: %{}}
      end
    end
  end

  describe "configure_debug/2" do
    test "enables true as normal debug" do
      Telemetry.configure_debug(@test_instance, true)
      assert Telemetry.debug_level(@test_instance) == :on
    end

    test "enables :verbose" do
      Telemetry.configure_debug(@test_instance, :verbose)
      assert Telemetry.debug_level(@test_instance) == :verbose
    end

    test "keeps debug off for false" do
      Telemetry.configure_debug(@test_instance, false)
      assert Telemetry.debug_level(@test_instance) == :off
    end

    test "disables a stale override when debug is absent" do
      Telemetry.set_debug(@test_instance, :on)
      Telemetry.configure_debug(@test_instance, nil)
      assert Telemetry.debug_level(@test_instance) == :off
    end
  end

  describe "per-instance isolation" do
    test "debug state is isolated between instances" do
      instance_a = :"jido_debug_test_a_#{System.unique_integer([:positive])}"
      instance_b = :"jido_debug_test_b_#{System.unique_integer([:positive])}"

      on_exit(fn ->
        Telemetry.set_debug(instance_a, :off)
        Telemetry.set_debug(instance_b, :off)
      end)

      Telemetry.set_debug(instance_a, :on)
      Telemetry.set_debug(instance_b, :verbose)

      assert Telemetry.debug_level(instance_a) == :on
      assert Telemetry.debug_level(instance_b) == :verbose

      Telemetry.set_debug(instance_a, :off)
      assert Telemetry.debug_level(instance_a) == :off
      assert Telemetry.debug_level(instance_b) == :verbose
    end
  end
end
