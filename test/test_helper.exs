# Prepare modules for Mimic
Enum.each(
  [
    :telemetry,
    System,
    Req,
    Jido.Supervisor,
    Jido.Agent.Lifecycle,
    Jido.Agent.Utilities,
    Jido.Discovery,
    Jido.Signal.ID
  ],
  &Mimic.copy/1
)

# Suite requires debug level for all tests
require Logger
Logger.configure(level: :debug)

ExUnit.start(capture_log: true)

ExUnit.configure(exclude: [:skip])
