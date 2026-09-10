# 04_01 Scheduled Signals

An Agent uses Scheduler Directives to create later work after its current Turn commits.

## What you will learn

- How one-shot, recurring, and cancellation Directives change Scheduler state.
- Why the scheduled Signal runs as a separate Turn and commit.

## Read the code

Read [the scheduled counter](scheduled_counter.ex), then read its behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_01_scheduled_signals --include example --seed 0
```

Expected result: a one-shot schedule increments the counter in a second Turn,
and a recurring schedule can be added and cancelled.

## Important behavior

The request state commits before the Scheduler handles its Directive. Invalid
delays and schedule expressions do not change Agent or Plugin state.

## Limits

This example does not prove durable occurrence recovery. That contract appears
in `04_11_durable_scheduling`.

## Files

- [Source](scheduled_counter.ex)
- [Tests](../../../test/examples/04_runtime/04_01_scheduled_signals/scheduled_counter_test.exs)

Previous: [Output Repair](../../03_llm/03_06_output_repair/README.md) | Next: [Keyed Timers](../04_02_keyed_timers/README.md)
