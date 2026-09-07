defmodule JidoTest.Eventually do
  @moduledoc """
  Polling-based assertions for async tests.

  Replaces flaky Process.sleep-based assertions with reliable polling.

  ## Examples

      # Wait for a condition
      eventually(fn -> GenServer.call(pid, :ready?) end)

      # Assert with custom timeout
      assert_eventually some_async_condition?(), timeout: 1000
  """

  @default_timeout 500
  @default_interval 5

  @doc """
  Polls until `fun.()` returns truthy or timeout.

  ## Options

    * `:timeout` - Maximum time to wait in milliseconds (default: #{@default_timeout})
    * `:interval` - Time between polls in milliseconds (default: #{@default_interval})

  ## Examples

      eventually(fn -> Process.alive?(pid) end)
      eventually(fn -> counter > 0 end, timeout: 1000)
  """
  def eventually(fun, opts \\ []) when is_function(fun, 0) or is_function(fun, 1) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    interval = Keyword.get(opts, :interval, @default_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    previous_deadline = Process.put({__MODULE__, :deadline}, deadline)

    try do
      do_eventually(fun, deadline, interval, nil)
    after
      restore_deadline(previous_deadline)
    end
  end

  defp do_eventually(fun, deadline, interval, last_result) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining < 0 do
      raise ExUnit.AssertionError,
        message: "Condition not met within timeout. Last result: #{inspect(last_result)}"
    end

    result = if is_function(fun, 1), do: fun.(remaining), else: fun.()

    case {result, System.monotonic_time(:millisecond) <= deadline} do
      {truthy, true} when truthy not in [nil, false] ->
        truthy

      {result, true} ->
        Process.sleep(min(interval, max(deadline - System.monotonic_time(:millisecond), 0)))
        do_eventually(fun, deadline, interval, result)

      {result, false} ->
        raise ExUnit.AssertionError,
          message: "Condition not met within timeout. Last result: #{inspect(result)}"
    end
  end

  @doc false
  def remaining_timeout(default) when is_integer(default) and default > 0 do
    case Process.get({__MODULE__, :deadline}) do
      nil -> default
      deadline -> max(min(deadline - System.monotonic_time(:millisecond), default), 1)
    end
  end

  defp restore_deadline(nil), do: Process.delete({__MODULE__, :deadline})
  defp restore_deadline(deadline), do: Process.put({__MODULE__, :deadline}, deadline)

  @doc """
  Assert-style wrapper for eventually.

  ## Examples

      assert_eventually Process.alive?(pid)
      assert_eventually counter > 0, timeout: 1000
  """
  defmacro assert_eventually(expr, opts \\ []) do
    quote do
      JidoTest.Eventually.eventually(fn -> unquote(expr) end, unquote(opts))
    end
  end

  @doc """
  Refute-style wrapper - waits until condition becomes falsy or timeout.

  Useful for asserting that something eventually stops or becomes false.
  """
  defmacro refute_eventually(expr, opts \\ []) do
    quote do
      JidoTest.Eventually.eventually(fn -> not unquote(expr) end, unquote(opts))
    end
  end
end
