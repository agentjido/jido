# 08_15 Pending Job Recovery

An Agent saves approval and requires an explicit new attempt after runtime loss.

## What you will learn

- How request, approval, retry, and completion use separate Turns.
- How stable job and attempt IDs reject stale results after restore.

## Read the code

Read [the pending-job Agent](pending_job_recovery.ex), then the local
[job runtime](job_runtime.ex), and then the behavior test.

## Run it

```sh
mix test test/examples/08_runtime/08_15_pending_job_recovery --include example --seed 0
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
- [Local job runtime](job_runtime.ex)
- [Tests](../../../test/examples/08_runtime/08_15_pending_job_recovery/pending_job_recovery_test.exs)

Previous: [State Migration](../08_14_state_migration/README.md) |
Next: [Multi-Agent](../../09_multi_agent/README.md)
