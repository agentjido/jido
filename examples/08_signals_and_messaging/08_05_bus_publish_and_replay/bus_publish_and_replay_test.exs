Code.require_file("bus_publish_and_replay.ex", __DIR__)

defmodule Jido.Examples.Signals.BusPublishAndReplayTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.Signals.BusPublishAndReplay, as: Example
  alias Jido.Signal.Bus

  test "stores before ordered delivery and supports replay" do
    name = "example-bus-#{System.unique_integer([:positive])}"
    bus = start_supervised!({Jido.Signal.Bus, name: name, max_log_size: 100})
    assert {:ok, _subscription_id} = Bus.subscribe(bus, "examples.inventory.*")

    assert {:ok, [first]} = Example.publish(bus, "examples.inventory.created", 1)
    assert {:ok, [second]} = Example.publish(bus, "examples.inventory.updated", 2)

    assert_receive {:signal, signal_one}
    assert_receive {:signal, signal_two}
    assert [signal_one.data.value, signal_two.data.value] == [1, 2]

    assert {:ok, [^first, ^second]} = Bus.replay(bus, "examples.inventory.*")
  end
end
