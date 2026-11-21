defmodule Jido.Examples.Signals.DurableSubscription do
  alias Jido.Signal.Bus

  @durable_id "examples-durable-reader"

  def attach(bus, target) do
    Bus.subscribe(bus, "examples.durable.*", durable: @durable_id, target: target)
  end

  def acknowledge(bus, cursor), do: Bus.ack(bus, @durable_id, cursor)
end
