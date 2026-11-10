defmodule Jido.Signal.Dispatch.LoggerAdapterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Signal
  alias Jido.Signal.Dispatch
  alias Jido.Signal.Dispatch.LoggerAdapter

  setup do
    original = Application.get_env(:jido, :default_log_level)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido, :default_log_level)
      else
        Application.put_env(:jido, :default_log_level, original)
      end
    end)
  end

  test "validates Logger options through Dispatch" do
    assert {:ok, {:logger, opts}} =
             Dispatch.validate_opts({:logger, level: :warning, structured: true, include_data: false})

    assert opts == [level: :warning, structured: true, include_data: false]

    assert {:error, message} = Dispatch.validate_opts({:logger, level: :notice})
    assert message =~ "level"
  end

  test "logs plain text with redacted data" do
    signal = signal(%{password: "hidden", value: 42})

    log =
      capture_log([level: :warning], fn ->
        assert :ok = LoggerAdapter.deliver(signal, level: :warning)
      end)

    assert log =~ "SIGNAL: log.test from /test"
    assert log =~ "[REDACTED]"
    refute log =~ "hidden"
  end

  test "does not log sensitive pairs in mixed or improper lists" do
    signal =
      signal(%{
        mixed: [{:password, "mixed-secret"}, :tail],
        improper: [{:token, "improper-secret"} | :tail]
      })

    log =
      capture_log(fn ->
        assert :ok = LoggerAdapter.deliver(signal, [])
      end)

    assert log =~ "[REDACTED]"
    refute log =~ "mixed-secret"
    refute log =~ "improper-secret"
  end

  test "can omit data from plain text" do
    signal = signal(%{value: 42})

    log =
      capture_log(fn ->
        assert :ok = LoggerAdapter.deliver(signal, include_data: false)
      end)

    assert log =~ "SIGNAL: log.test from /test"
    refute log =~ "with data="
  end

  test "does not log secrets in compound map keys" do
    signal = signal(%{{:password, "compound-log-secret"} => :safe})

    log = capture_log(fn -> assert :ok = LoggerAdapter.deliver(signal, []) end)

    assert log =~ "[REDACTED]"
    refute log =~ "compound-log-secret"
  end

  test "logs a structured and sanitized message" do
    signal = signal(%{token: "hidden", value: 42})

    log =
      capture_log(fn ->
        assert :ok = LoggerAdapter.deliver(signal, structured: true)
      end)

    assert log =~ "signal_dispatched"
    assert log =~ "[REDACTED]"
    refute log =~ "hidden"
  end

  test "uses log_level before level and falls back to the application default" do
    signal = signal(%{})
    Application.put_env(:jido, :default_log_level, :warning)

    log =
      capture_log([level: :warning], fn ->
        assert :ok = LoggerAdapter.deliver(signal, level: :error, log_level: :warning)
        assert :ok = LoggerAdapter.deliver(signal, level: :invalid)
      end)

    assert length(Regex.scan(~r/SIGNAL: log\.test/, log)) == 2
  end

  defp signal(data), do: Signal.new!("log.test", data, source: "/test")
end
