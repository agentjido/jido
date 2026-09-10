# 04_10 Pending Job Recovery

An Agent saves approval and requires an explicit new attempt after runtime loss.

## What you will learn

- How request, approval, retry, and completion use separate Turns.
- How stable job and attempt IDs reject stale results after restore.

## Read the code

Read [the pending-job Agent](pending_job_recovery.ex), then the shared
[job runtime](../support/job_runtime.ex), and then the behavior test.

## Run it

```sh
mix test test/examples/04_runtime/04_10_pending_job_recovery --include example --seed 0
```

Expected result: saved approval survives Agent loss, no Task appears on restore,
and an explicit retry starts a new attempt that rejects the old result.

## Important behavior

The `:running` state records an accepted attempt. It does not prove that a Task
is still alive. The caller must choose retry or cancellation after loss.

## Limits

Jido does not choose the retry policy or generate application attempt IDs. The
runtime service must be supplied again when a retry needs a non-default client.

## Files

- [Agent](pending_job_recovery.ex)
- [Shared job runtime](../support/job_runtime.ex)
- [Tests](../../../test/examples/04_runtime/04_10_pending_job_recovery/pending_job_recovery_test.exs)

Previous: [Recoverable Delivery](../04_09_recoverable_delivery/README.md) | Next: [Durable Scheduling](../04_11_durable_scheduling/README.md)
