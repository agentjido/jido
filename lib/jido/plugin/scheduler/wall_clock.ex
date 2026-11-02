defmodule Jido.Plugin.Scheduler.WallClock do
  @moduledoc false

  @spec wait_until(DateTime.t()) :: :ok | :cancelled
  def wait_until(time) do
    wait_until(time, &DateTime.utc_now/0, &wait/1)
  end

  @doc false
  def wait_until(time, now, wait_fun) do
    remaining = DateTime.diff(time, now.(), :microsecond)

    if remaining > 0 do
      case wait_fun.(ceil_milliseconds(remaining)) do
        :ok -> wait_until(time, now, wait_fun)
        :cancelled -> :cancelled
      end
    else
      :ok
    end
  end

  defp ceil_milliseconds(microseconds), do: div(microseconds + 999, 1_000)

  defp wait(delay) do
    receive do
      :shutdown -> :cancelled
    after
      delay -> :ok
    end
  end
end
