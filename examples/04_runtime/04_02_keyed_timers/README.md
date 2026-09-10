# 04_02 Keyed Timers

An Agent and Plugin combine replaceable OTP timers with an ordered batch policy.

## What you will learn

- How a Plugin runtime owns transient keyed timers.
- How Agent state uses timer generations to reject stale timeout Signals.

## Read the code

Read [the burst buncher](burst_buncher.ex) first. Then read the
[Timer Plugin](timer.ex) and the behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_02_keyed_timers --include example --seed 0
```

Expected result: a size or timeout flush emits one ordered batch, while stale
timer generations and duplicate item IDs do not drain the current buffer.

## Important behavior

Agent state owns the buffer and generation. The Plugin owns only live timers.
The buffer commits before the emitted batch is dispatched.

## Limits

The timers are not durable. Plugin or Agent loss removes pending timer processes.

## Files

- [Agent](burst_buncher.ex)
- [Timer Plugin](timer.ex)
- [Tests](../../../test/examples/04_runtime/04_02_keyed_timers/burst_buncher_test.exs)

Previous: [Scheduled Signals](../04_01_scheduled_signals/README.md) | Next: [Bus Delivery](../04_03_bus_delivery/README.md)
