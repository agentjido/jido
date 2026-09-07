defmodule Jido.Plugin.Scheduler.WallClock do
  @moduledoc false

  @spec wait_until(DateTime.t()) :: :ok
  def wait_until(time) do
    wait_until(time, &DateTime.utc_now/0, &wait/1)
  end

  @doc false
  def wait_until(time, now, wait_fun) do
    remaining = DateTime.diff(time, now.(), :microsecond)

    if remaining > 0 do
      :ok = wait_fun.(div(remaining + 999, 1_000))
      wait_until(time, now, wait_fun)
    else
      :ok
    end
  end

  defp wait(delay) do
    receive do
    after
      delay -> :ok
    end
  end
end
