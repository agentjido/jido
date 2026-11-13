# 11_03 Keyed Timers

An Agent and Plugin combine replaceable OTP timers with an ordered batch policy.

## What you will learn

- How a Plugin runtime owns transient keyed timers.
- How Agent state uses timer generations to reject stale timeout Signals.

## Read the code

Read [the burst buncher](burst_buncher.ex) first. Then read the
[Timer Plugin](timer.ex) and the behavior test.

## Run it

```sh
mix test.examples examples/11_built_in_capabilities/11_03_keyed_timers --warnings-as-errors
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
- [Tests](burst_buncher_test.exs)

Previous: [Scheduled Signals](../11_02_scheduled_signals/README.md) | Next: [Heartbeat](../11_04_heartbeat/README.md)
