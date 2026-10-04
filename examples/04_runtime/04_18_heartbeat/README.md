# 04_18 Heartbeat

The Heartbeat Plugin owns a timer and sends periodic Signals to its Agent.

## What you will learn

- How the default `jido.agent.heartbeat` Signal enters the normal Turn path.
- How to select a custom Signal type, data map, source, and interval.
- How invalid Plugin options fail during definition validation.
- How Jido replaces the Plugin runtime and stops it with the Agent owner.

## Read the code

Read [the two Heartbeat Agents](heartbeat.ex). One uses the default Signal type.
The other uses an application Signal type. Both keep the interval long so the
behavior test can trigger each tick through an explicit synchronization point.

## Run it

```sh
mix test test/examples/04_runtime/04_18_heartbeat --include example --seed 0
```

Expected result: explicit ticks produce the configured Signals. An invalid
interval is rejected. A failed runtime is replaced, and Agent shutdown stops
the replacement.

## Important behavior

Each tick uses `AgentServer.cast/2`, so it follows best-effort cast delivery
under overload. The timer is runtime state. The Agent stores only domain data
that its normal route selects from the Signal.

Plugin option validation happens before runtime work starts. The interval must
be a positive integer. Signal type and source must be valid nonempty strings,
and Signal data must be a plain map.

## Limits

A Heartbeat is a periodic input. It is not a durable schedule. Use the durable
scheduling and persistence lessons when a missed occurrence must be recovered.

## Files

- [Source](heartbeat.ex)
- [Tests](../../../test/examples/04_runtime/04_18_heartbeat/heartbeat_test.exs)

Previous: [Failure Outcome](../04_17_failure_outcome/README.md) | Next: [Multi-agent examples](../../05_multi_agent/README.md)
