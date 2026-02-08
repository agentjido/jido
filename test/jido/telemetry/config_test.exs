defmodule JidoTest.Telemetry.ConfigTest do
  use ExUnit.Case, async: false

  alias Jido.Telemetry.Config

  setup do
    previous = Application.get_env(:jido, :telemetry)

    on_exit(fn ->
      if previous == nil do
        Application.delete_env(:jido, :telemetry)
      else
        Application.put_env(:jido, :telemetry, previous)
      end
    end)

    :ok
  end

  test "defaults log level to :info when unset" do
    Application.delete_env(:jido, :telemetry)
    assert Config.log_level() == :info
  end

  test "falls back to :info for invalid log level" do
    Application.put_env(:jido, :telemetry, log_level: :verbose)
    assert Config.log_level() == :info
  end

  test "reads valid log level from runtime config" do
    Application.put_env(:jido, :telemetry, log_level: :error)
    assert Config.log_level() == :error
  end
end
