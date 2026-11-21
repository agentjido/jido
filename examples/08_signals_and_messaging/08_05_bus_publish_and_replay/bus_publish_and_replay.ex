defmodule Jido.Examples.Signals.BusPublishAndReplay do
  alias Jido.Signal.Bus

  def start_link(name), do: Bus.start_link(name: name, max_log_size: 100)

  def publish(bus, type, value) do
    signal = Jido.Signal.new!(type, %{value: value}, source: "/examples/bus")
    Bus.publish(bus, [signal])
  end
end
