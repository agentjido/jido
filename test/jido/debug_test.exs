defmodule JidoTest.DebugTest do
  use ExUnit.Case, async: false

  alias Jido.Debug

  @test_instance :"jido_debug_test_#{System.unique_integer([:positive])}"

  setup do
    instance_config = Application.fetch_env(:jido_test, @test_instance)
    telemetry = Application.fetch_env(:jido, :telemetry)

    on_exit(fn ->
      restore_env(:jido_test, @test_instance, instance_config)
      restore_env(:jido, :telemetry, telemetry)
      Debug.reset(@test_instance)
    end)

    Application.delete_env(:jido_test, @test_instance)
    Application.delete_env(:jido, :telemetry)
    Debug.reset(@test_instance)

    :ok
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)

  describe "enable/2 and level/1" do
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
      assert Debug.override(@test_instance, :semantic_log_mode) == nil
    end

    test "returns override when :on" do
      Debug.enable(@test_instance, :on)
      assert Debug.override(@test_instance, :semantic_log_mode) == :interesting
    end

    test "returns override when :verbose" do
      Debug.enable(@test_instance, :verbose)
      assert Debug.override(@test_instance, :semantic_log_mode) == :all
    end

    test "returns nil for unknown override key" do
      Debug.enable(@test_instance, :on)
      assert Debug.override(@test_instance, :nonexistent_key) == nil
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
      assert status.overrides.semantic_log_mode == :interesting
    end

    test "malformed runtime state uses the disabled defaults" do
      for state <- [:invalid, %{}, %{level: :invalid}, %{level: :on, overrides: :invalid}] do
        :persistent_term.put({:jido_debug, @test_instance}, state)

        assert Debug.level(@test_instance) == :off
        refute Debug.enabled?(@test_instance)
        assert Debug.override(@test_instance, :semantic_log_mode) == nil
        assert Debug.status(@test_instance) == %{level: :off, overrides: %{}}
      end
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

    test "disables stale runtime override when debug config is absent" do
      Debug.enable(@test_instance, :on)
      Application.put_env(:jido_test, @test_instance, [])

      Debug.maybe_enable_from_config(:jido_test, @test_instance)
      assert Debug.level(@test_instance) == :off

      Application.delete_env(:jido_test, @test_instance)
    end

    test "malformed instance configuration disables stale runtime state" do
      Debug.enable(@test_instance, :on)
      Application.put_env(:jido_test, @test_instance, :invalid_container)

      assert Debug.maybe_enable_from_config(:jido_test, @test_instance) == :ok
      assert Debug.level(@test_instance) == :off
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
end
