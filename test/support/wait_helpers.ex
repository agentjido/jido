defmodule JidoTest.WaitHelpers do
  @moduledoc """
  Minimal polling helpers for async assertions in tests.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @doc """
  Waits until `fun` returns a truthy value.

  ## Options

  - `:timeout` - Maximum time to wait in milliseconds (default: 1000)
  - `:interval` - Polling interval in milliseconds (default: 10)
  - `:label` - Label included in timeout failures (default: "condition")
  """
  @spec wait_until((-> boolean()), keyword()) :: :ok
  def wait_until(fun, opts \\ []) when is_function(fun, 0) do
    timeout_ms = Keyword.get(opts, :timeout, 1000)
    interval_ms = Keyword.get(opts, :interval, 10)
    label = Keyword.get(opts, :label, "condition")

    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, interval_ms, deadline, label)
  end

  defp do_wait_until(fun, interval_ms, deadline, label) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Timed out waiting for #{label}")
      else
        Process.sleep(interval_ms)
        do_wait_until(fun, interval_ms, deadline, label)
      end
    end
  end
end
