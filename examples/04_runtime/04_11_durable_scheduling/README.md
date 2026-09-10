# 04_11 Durable Scheduling

An Agent saves due schedule occurrences and acknowledges each one with its result.

## What you will learn

- How durable Scheduler occurrences survive Agent and Plugin loss.
- How admission, generation checks, and acknowledgement prevent stale work.

## Read the code

Read [the Agent](scheduled_occurrence_recovery.ex), then the named
[occurrence Actions](occurrence_actions.ex), and then the behavior test. The
Actions are named because they are the explicit handlers for the Scheduler
occurrence protocol and are reused by alternative Scheduler configurations.

## Run it

```sh
mix test test/examples/04_runtime/04_11_durable_scheduling --include example --seed 0
```

Expected result: an acknowledged occurrence remains complete after restore and
the recurring schedule continues with a new occurrence.

## Important behavior

The Scheduler keeps one pending occurrence per job. It retries saved work until
the result Turn acknowledges the occurrence, and it rejects stale generations.

## Limits

The example keeps an unbounded list of captured ticks for inspection. A
long-running application needs bounded result storage.

## Files

- [Agent](scheduled_occurrence_recovery.ex)
- [Occurrence Actions](occurrence_actions.ex)
- [Tests](../../../test/examples/04_runtime/04_11_durable_scheduling/durable_scheduling_test.exs)

Previous: [Pending Job Recovery](../04_10_pending_job_recovery/README.md) | Next: [Multi-agent examples](../../05_multi_agent/README.md)
