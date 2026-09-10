# 04_09 Recoverable Delivery

An Agent saves business state and external delivery intent in one checkpoint.

## What you will learn

- How Plugin-owned state records pending and completed effect IDs.
- How a supervised worker resumes saved intent after Agent restore.

## Read the code

Read [the Agent](recoverable_delivery.ex), then the
[delivery Plugin](delivery_plugin.ex), [worker](delivery_worker.ex),
[sink contract](sink.ex), and [memory sink](support/memory_sink.ex).

## Run it

```sh
mix test test/examples/04_runtime/04_09_recoverable_delivery --include example --seed 0
```

Expected result: intent saved while the sink is unavailable resumes after
restore, commits a confirmation, and produces one idempotent external record.

## Important behavior

Delivery is at least once. The application owns stable effect IDs, and the sink
must treat a repeated ID and value as success. A different value for the same ID
is an error.

## Limits

The memory sink is local and not durable. Completed IDs remain in state, so a
production application needs a retention policy.

## Files

- [Agent](recoverable_delivery.ex)
- [Delivery Plugin](delivery_plugin.ex)
- [Worker](delivery_worker.ex)
- [Sink contract](sink.ex)
- [Memory sink](support/memory_sink.ex)
- [Demo](demo.exs)
- [Tests](../../../test/examples/04_runtime/04_09_recoverable_delivery/recoverable_delivery_test.exs)

Previous: [Causal Trace](../04_08_causal_trace/README.md) | Next: [Pending Job Recovery](../04_10_pending_job_recovery/README.md)
