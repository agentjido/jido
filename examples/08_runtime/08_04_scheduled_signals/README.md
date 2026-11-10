# 08_04 Scheduled Signals

An Agent uses Scheduler Directives to create later work after its current Turn commits.

## What you will learn

- How one-shot, recurring, and cancellation Directives change Scheduler state.
- Why the scheduled Signal runs as a separate Turn and commit.

## Read the code

Read [the scheduled counter](scheduled_counter.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/08_runtime/08_04_scheduled_signals --include example --seed 0
```

Expected result: a one-shot schedule increments the counter in a second Turn,
and a recurring schedule can be added and cancelled.

## Important behavior

The request state commits before the Scheduler handles its Directive. Invalid
delays and schedule expressions do not change Agent or Plugin state.

## Limits

The Scheduler restores future recurring timers from saved Agent state. It does
not save, retry, or acknowledge the work that a timer emits. Use explicit
application state or a durable Signal Bus when that work must survive loss.

## Files

- [Source](scheduled_counter.ex)
- [Tests](../../../test/examples/08_runtime/08_04_scheduled_signals/scheduled_counter_test.exs)

Previous: [Failure Outcome](../08_03_failure_outcome/README.md) |
Next: [Keyed Timers](../08_05_keyed_timers/README.md)
