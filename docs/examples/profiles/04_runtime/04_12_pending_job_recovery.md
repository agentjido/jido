# Pending Job Recovery

Feature ID: `04_12_pending_job_recovery`. Status: implemented within the tested scope.

## Added feature

Saved input, approval, attempt identity, retry, cancellation, and stale-result
rejection recover after Agent, Plugin, parent, or VM loss.

## Evidence

Seven core tests cover pure admission rules and process and VM recovery.

```shell
mix test test/jido/agent/pending_job_recovery_test.exs test/jido/agent/pending_job_vm_recovery_test.exs --seed 0
```

[Source](../../../../examples/04_runtime/04_12_pending_job_recovery/pending_job_recovery.ex) ·
[Core tests](../../../../test/jido/agent/pending_job_recovery_test.exs) ·
[Results](../../rec-02-results.md)
