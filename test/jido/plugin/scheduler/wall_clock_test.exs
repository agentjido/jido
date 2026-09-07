defmodule Jido.Plugin.Scheduler.WallClockTest do
  use ExUnit.Case, async: true

  alias Jido.Plugin.Scheduler.WallClock

  test "waits for each positive remainder and rounds microseconds up" do
    slot = ~U[2030-01-01 00:00:01.000000Z]
    tag = make_ref()

    for time <- [
          ~U[2030-01-01 00:00:00.000000Z],
          ~U[2030-01-01 00:00:00.999500Z],
          slot
        ],
        do: send(self(), {tag, time})

    now = fn ->
      receive do
        {^tag, time} -> time
      end
    end

    wait = fn delay ->
      send(self(), {:wait, delay})
      :ok
    end

    assert :ok = WallClock.wait_until(slot, now, wait)
    assert_received {:wait, 1_000}
    assert_received {:wait, 1}
    refute_received {:wait, _delay}
  end

  test "does not wait after the clock reaches the slot" do
    wait = fn _delay -> flunk("unexpected wait") end

    assert :ok =
             WallClock.wait_until(
               ~U[2030-01-01 00:00:01Z],
               fn -> ~U[2030-01-01 00:00:02Z] end,
               wait
             )
  end
end
