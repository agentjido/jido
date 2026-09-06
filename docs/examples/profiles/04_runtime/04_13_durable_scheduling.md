# Durable Scheduling

Feature ID: `04_13_durable_scheduling`. Status: implemented within the tested scope.

## Added feature

The Scheduler saves one logical occurrence before delivery and removes it only
when the business result commits. Generation and occurrence identity reject
stale or duplicate work.

## Evidence

Thirty-one core tests cover identity, Agent and Plugin loss, recovery,
cancellation, generation change, failed writes, and bounded pending work.
They also verify a configured delivery interval and reject invalid intervals.
The interval test uses the same saved occurrence across rejected result writes,
then confirms that one successful result commit clears it.

```shell
mix test test/jido/plugin/scheduler_occurrence_test.exs test/jido/agent/scheduled_occurrence_test.exs test/jido/plugin/durable_scheduler_test.exs test/jido/agent/scheduled_occurrence_recovery_test.exs --seed 0
```

[Source](../../../../examples/04_runtime/04_13_durable_scheduling/scheduled_occurrence_recovery.ex) ·
[Core tests](../../../../test/jido/agent/scheduled_occurrence_recovery_test.exs) ·
[Results](../../rec-03-results.md)
