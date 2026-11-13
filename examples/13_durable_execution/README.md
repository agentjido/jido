# 13 Durable Flow and Agent Execution

This chapter keeps `Jido.Durable` and durable AgentServer hosting in one
recovery path. Every example runs with local storage and no external service.

## Choose the runtime mode

Use durable AgentServer hosting when a stable logical Agent owns domain state,
routes Signals, and may activate or passivate. Use `Jido.Durable` when the
application owns a durable Flow run and reads or resumes it through the facade.
Both modes save Flow progress at component boundaries. Neither mode resumes in
the middle of an Action, makes external I/O exactly once, or creates one atomic
checkpoint for a parent and all child Agents.

The AgentServer lessons come first because they add logical identity, state
commit, and process lifecycle. The `Jido.Durable` lessons then show the same
Flow wait and recovery contracts without an Agent domain owner.

## AgentServer recovery proofs

1. [Saved Agent State](13_01_saved_agent/README.md) restores committed state.
2. [Saved Progress](13_02_saved_progress/README.md) resumes one Flow step after process loss.
3. [VM Recovery](13_03_vm_recovery/README.md) restores the same Turn in a fresh BEAM.
4. [Accepted Work](13_04_accepted_work/README.md) runs durable work in a topology member.
5. [Saved Completion](13_05_saved_completion/README.md) restores a completion after a lost write reply.
6. [Durable Approval Agent](13_06_durable_wait/README.md) passivates, resumes,
   and deduplicates one approval Turn.
7. [External Uncertainty](13_07_external_uncertainty/README.md) repeats one operation ID after uncertain I/O.
8. [Waterpark](13_08_waterpark/README.md) activates and passivates a bounded Agent fleet.

## `Jido.Durable` Flow proofs

9. [Start and Result](13_09_durable_flow_start/README.md) starts and reads one durable Flow.
10. [Restart Recovery](13_10_durable_flow_restart/README.md) restores an open Flow wait.
11. [Signal Resume](13_11_durable_signal_resume/README.md) resumes saved work with a Signal.
12. [Timed Resume](13_12_durable_timed_resume/README.md) resumes at a reported wake time.
13. [Pending Job Recovery](13_13_pending_job_recovery/README.md) retries
    accepted post-commit work after runtime loss.

## Recovery rule

```text
save acceptance with Agent -> run step -> confirm checkpoint -> run next step
Flow completes -> save candidate Agent and completion together -> release Turn
```

Recovery starts at the next unconfirmed component boundary. It does not resume
inside an Action. External I/O in an Action can repeat.

## Ownership

| Owner | Responsibility |
| --- | --- |
| OTP supervisor | Restart processes in the current BEAM. |
| AgentServer | Accept, checkpoint, restore, cancel, and commit one current Turn. |
| Agent | Hold committed domain state. |
| Runic | Hold and restore Flow graph progress. |
| Application | Own storage, compatible code, and activation of known roots. |

## Limits

Caller handles and queued Signals do not survive a crash. A repeated Signal is
a new Turn unless the application or saved receipt identifies it as a retry.
Post-commit hooks and effects are not replayed. Topology members use separate
records. A parent record is not one coordinated checkpoint for all members.
These examples prove process and BEAM loss with retained local storage. They do
not prove host loss, storage loss, cluster takeover, or exactly-once I/O.

## Run it

```sh
mix test.examples examples/13_durable_execution --warnings-as-errors
```

Child BEAM tests require local sockets and `kill`. They do not require network
services or credentials.

Previous: [Persistence](../12_persistence/README.md)
