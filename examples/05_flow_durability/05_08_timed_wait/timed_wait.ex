defmodule Jido.Examples.Durability.TimedWait do
  @moduledoc "Waits for a host-driven durable timer."
  use Jido.Flow, name: "example_durable_timed_wait"

  flow do
    timer "wake", after_ms: 60_000
    output result("wake")
  end
end
