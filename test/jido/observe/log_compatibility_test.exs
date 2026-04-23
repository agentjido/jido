defmodule JidoTest.Observe.LogCompatibilityTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Debug
  alias Jido.Observe
  alias Jido.Observe.Log

  @test_instance :"jido_observe_log_compat_#{System.unique_integer([:positive])}"

  setup do
    previous_level = Logger.level()
    Logger.configure(level: :debug)

    original_observability = Application.get_env(:jido, :observability)
    Debug.reset(@test_instance)

    on_exit(fn ->
      Logger.configure(level: previous_level)

      if original_observability do
        Application.put_env(:jido, :observability, original_observability)
      else
        Application.delete_env(:jido, :observability)
      end

      Debug.reset(@test_instance)
    end)

    :ok
  end

  describe "Jido.Observe.log/3" do
    test "preserves the threshold-based logging facade" do
      Application.put_env(:jido, :observability, log_level: :info)

      log =
        capture_log(fn ->
          Observe.log(:debug, "compat facade suppressed")
          Observe.log(:info, "compat facade emitted")
        end)

      refute log =~ "compat facade suppressed"
      assert log =~ "compat facade emitted"
    end
  end

  describe "Jido.Observe.Log.threshold/0" do
    test "reads the observability log level from config" do
      Application.put_env(:jido, :observability, log_level: :warning)

      assert Log.threshold() == :warning
    end
  end

  describe "Jido.Observe.Log.log/3" do
    test "honors the global observability log level" do
      Application.put_env(:jido, :observability, log_level: :warning)

      log =
        capture_log(fn ->
          Log.log(:info, "compat log suppressed")
          Log.log(:error, "compat log emitted")
        end)

      refute log =~ "compat log suppressed"
      assert log =~ "compat log emitted"
    end

    test "honors per-instance debug overrides via :jido_instance metadata" do
      Application.put_env(:jido, :observability, log_level: :warning)
      Debug.enable(@test_instance, :on)

      log =
        capture_log(fn ->
          Log.log(:debug, "compat debug override emitted", jido_instance: @test_instance)
        end)

      assert log =~ "compat debug override emitted"
    end
  end
end
