# 11_04 Heartbeat

A static Timer interval sends periodic Signals to its Agent. Heartbeat is the
application meaning of the Signal, not a separate timer engine.

## What you will learn

- How the default `jido.agent.heartbeat` Signal enters the normal Turn path.
- How to select a custom Signal type, data map, source, and interval.
- How invalid Timer options fail during definition validation.
- How Jido replaces the Plugin runtime and stops it with the Agent owner.

## Read the code

Read [the two periodic Agents](heartbeat.ex). One uses the default Signal type.
The other uses an application Signal type. Both declare one static Timer
interval.

## Run it

```sh
mix test.examples examples/11_built_in_capabilities/11_04_heartbeat --warnings-as-errors
```

Expected result: Timer produces the configured Signals. An invalid interval is
rejected. A failed Timer runtime is replaced, and Agent shutdown stops the
replacement.

## Important behavior

Each tick uses `AgentServer.cast/2`, so it follows best-effort cast delivery
under overload. The interval definition is in Timer Agent state. The live timer
reference stays in the runtime.

Plugin option validation happens before runtime work starts. The interval must
be a positive integer. Signal type and source must be valid nonempty strings,
and Signal data must be a plain map.

## Limits

A periodic Timer Signal does not replay occurrences that pass while its runtime
is offline. Use an external delivery design when missed work must be recovered.

## Files

- [Source](heartbeat.ex)
- [Tests](heartbeat_test.exs)

Previous: [Keyed Timers](../11_03_keyed_timers/README.md) |
Next: [Sensor Manager](../11_05_sensor_manager/README.md)
