# Durable Scheduling

Feature ID: `04_13_durable_scheduling`. Status: implemented within the tested scope.

## Added feature

The Scheduler saves one logical occurrence before delivery and removes it only
when the business result commits. Generation and occurrence identity reject
stale or duplicate work.

## Evidence

Twenty-five core tests cover identity, Agent and Plugin loss, recovery,
cancellation, generation change, failed writes, and bounded pending work.

```shell
mix test test/jido/plugin/scheduler_occurrence_test.exs test/jido/agent/scheduled_occurrence_test.exs test/jido/plugin/durable_scheduler_test.exs test/jido/agent/scheduled_occurrence_recovery_test.exs --seed 0
```

[Source](../../../../examples/04_runtime/04_13_durable_scheduling/scheduled_occurrence_recovery.ex) ·
[Core tests](../../../../test/jido/agent/scheduled_occurrence_recovery_test.exs) ·
[Results](../../rec-03-results.md)
