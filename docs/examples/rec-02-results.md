> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# REC-02: saved approval and explicit job recovery

Date: **2026-09-04**. Status: **Implemented with current core**.

The [Pending Job Recovery Agent](../../examples/04_runtime/04_12_pending_job_recovery/pending_job_recovery.ex)
reuses the existing Managed Jobs Plugin. It adds saved job input, approval,
explicit attempt IDs, retry, and cancellation policy. No new runtime engine
or automatic Directive replay is added.

```elixir
PendingJobRecovery.request_job(server, "job-1", 4)
PendingJobRecovery.approve_job(server, "job-1", "attempt-1")
# After the worker or Agent is lost and the Agent is restored:
PendingJobRecovery.retry_job(server, "job-1", "attempt-2")
```

A retry uses saved input and a new attempt ID. It cancels the previous task if
one still exists. The result must match the active attempt. Cancellation is
committed state and remains effective after restore. Approval is a separate
Turn and survives a restart. A waiting request can still be approved later.

`:running` means the last start request was committed; it does not prove a task
is alive. This example deliberately requires the caller to choose retry or
cancel after a loss. Runtime adapters remain in caller context. They are not
saved and must be supplied again if a retry needs them.

## Verification

```shell
mix test test/jido/agent/pending_job_recovery_test.exs test/jido/agent/pending_job_vm_recovery_test.exs --seed 0
```

All **seven tests pass, with no skips**:

- Pure approval and attempt validation; rejection of stale and duplicate results.
- A waiting approval request survives Agent loss.
- Agent loss permits explicit retry and rejects the previous result.
- Plugin loss permits explicit retry without replacing the Agent.
- Cancellation survives restart and rejects approval, retry, and late results.
- Parent loss stops child work; its saved request can be restored and retried.
- Loss of the old VM permits restore and retry in a different VM from the file checkpoint.

The last two cases use real owned child Agents and real File persistence.
`SpawnAgent` inherits persistence from the configured Jido instance. It does
not accept a per-child lifecycle override. The test instance uses a File-backed
adapter with a test-specific directory. For the VM case, the old VM is stopped
before another VM uses the directory. They never write it concurrently.

The work barrier holds the actual Managed Jobs Task. Its PID and function stay
in runtime context. The saved record contains the job input, approval, attempt
ID, and Agent state. After restore, retry and completion advance the revision
twice. A late result does not advance it.

## Limits

Recovery is explicit. It is not automatic activation, task continuation, or
remote placement. Retry can repeat external work; an application still needs
its own duplicate-effect policy. The example retains used job and attempt IDs
without a pruning policy. File recovery between VMs on one host does not prove
shared writes, a distributed lease, or power-loss durability.
