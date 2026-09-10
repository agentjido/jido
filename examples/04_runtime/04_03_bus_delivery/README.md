# 04_03 Bus Delivery

An Agent consumes ordered Signals from a durable local Bus subscription.

## What you will learn

- How the Bus Client Plugin routes matching records into Agent Turns.
- How commit acknowledgement, retry order, and stable Signal IDs work together.

## Read the code

Read [the Bus delivery Agent](bus_delivery.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_03_bus_delivery --include example --seed 0
```

Expected result: matching records commit in order, a failed Turn retries before
later input, and a restarted Client continues its subscription.

## Important behavior

The Bus acknowledges a record only after the Turn commits. The Agent accepts an
already committed Signal ID so that a repeated delivery can be acknowledged.

## Limits

The example Bus and cursor use local memory. This does not prove disk durability.

## Files

- [Source](bus_delivery.ex)
- [Tests](../../../test/examples/04_runtime/04_03_bus_delivery/bus_delivery_test.exs)

Previous: [Keyed Timers](../04_02_keyed_timers/README.md) | Next: [Managed Jobs](../04_04_managed_jobs/README.md)
