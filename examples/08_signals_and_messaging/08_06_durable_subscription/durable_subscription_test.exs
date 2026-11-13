Code.require_file("durable_subscription.ex", __DIR__)

defmodule Jido.Examples.Signals.DurableSubscriptionTest do
  use ExUnit.Case, async: false
  @moduletag :integration

  alias Jido.Examples.Signals.DurableSubscription, as: Example
  alias Jido.Signal.Bus
  alias Jido.Signal.Bus.RecordedSignal

  test "repeats an unacknowledged record after subscriber loss" do
    name = "example-durable-bus-#{System.unique_integer([:positive])}"
    bus = start_supervised!({Bus, name: name, max_log_size: 100})
    owner = self()

    subscriber =
      spawn(fn ->
        receive do
          message -> send(owner, {:relayed, message})
        end

        receive do
          :stop -> :ok
        end
      end)

    monitor = Process.monitor(subscriber)
    assert {:ok, "examples-durable-reader"} = Example.attach(bus, subscriber)

    signal = Jido.Signal.new!("examples.durable.created", %{}, source: "/durable")
    assert {:ok, [published]} = Bus.publish(bus, [signal])

    assert_receive {:relayed, {:signal, "examples-durable-reader", %RecordedSignal{} = first}}
    assert first.cursor == published.cursor

    Process.exit(subscriber, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^subscriber, :killed}

    assert {:ok, "examples-durable-reader"} = Example.attach(bus, self())
    assert_receive {:signal, "examples-durable-reader", %RecordedSignal{} = repeated}
    assert repeated.cursor == first.cursor
    assert :ok = Example.acknowledge(bus, repeated.cursor)
  end
end
