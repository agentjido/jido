> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../migration/10-execution-record.md) for the migration result.

# Runtime and Multi-agent feature review

Review date: **2026-09-04**.

Runtime has 13 feature fixtures and 93 passing tests. Multi-agent has six
feature fixtures and 38 passing tests. Each example adds one Jido capability.
Neither group has a skipped test.

## Runtime sequence

| Order | Added feature | Tests |
| --- | --- | ---: |
| [Scheduled Signals](profiles/04_runtime/04_01_scheduled_signals.md) | Scheduler dispatch and a later committed Turn | 3 example |
| [Keyed Timers](profiles/04_runtime/04_02_keyed_timers.md) | Replace and cancel one timer; reject stale generations | 4 example |
| [Bus Delivery](profiles/04_runtime/04_03_bus_delivery.md) | Input Plugin delivery, ordered acknowledgement, retry, and reconnect | 4 example |
| [Managed Jobs](profiles/04_runtime/04_04_managed_jobs.md) | Plugin-owned tasks, later results, cancellation, and cleanup | 6 example |
| [Runtime Inspection](profiles/04_runtime/04_05_runtime_inspection.md) | Read committed state and revision during active work | 2 example |
| [State Recovery](profiles/04_runtime/04_06_state_recovery.md) | Restore complete Agent state and duplicate history | 5 example |
| [Input Deduplication](profiles/04_runtime/04_07_input_deduplication.md) | Reject stable duplicate IDs before a new commit | 2 example |
| [Commit Outbox](profiles/04_runtime/04_08_commit_outbox.md) | Restore business state and delivery intent together | 3 example |
| [Agent Observation](profiles/04_runtime/04_09_agent_observation.md) | Lifecycle, Turn, commit, cancellation, and terminal events | 9 core |
| [Causal Trace](profiles/04_runtime/04_10_causal_trace.md) | Local and remote creation causes through retry and restart | 12 core |
| [Recoverable Delivery](profiles/04_runtime/04_11_recoverable_delivery.md) | Resume committed output intent after loss | 11 core |
| [Pending Job Recovery](profiles/04_runtime/04_12_pending_job_recovery.md) | Restore approval, attempt, retry, and cancellation state | 7 core |
| [Durable Scheduling](profiles/04_runtime/04_13_durable_scheduling.md) | Retry saved occurrences until commit acknowledgement | 25 core |

## Multi-agent sequence

| Order | Added feature | Tests |
| --- | --- | ---: |
| [Child Lifecycle](profiles/05_multi_agent/05_01_child_lifecycle.md) | Child ownership, restart state, PID replacement, and stop | 3 example |
| [Correlated Requests](profiles/05_multi_agent/05_02_correlated_requests.md) | Independent child Turns, stale reply rejection, failure, and deadlines | 6 example |
| [Bounded Workers](profiles/05_multi_agent/05_03_bounded_workers.md) | Concurrent children, queued work, ordered results, and group cancellation | 5 example |
| [Agent Hierarchy](profiles/05_multi_agent/05_04_agent_hierarchy.md) | Direct ownership, branch isolation, and subtree stop | 4 example |
| [Remote Child](profiles/05_multi_agent/05_05_remote_child.md) | Selected-node placement, remote Signals, ownership, and cleanup | 16 core |
| [Remote Lifecycle](profiles/05_multi_agent/05_06_remote_lifecycle.md) | Disconnect, node loss, parent loss, and replacement | 4 core |

The Multi-agent fixtures use built-in `SpawnAgent`, `EmitToChild`,
`EmitToParent`, and `StopChild` Directives. Test observers can hold or fail
execution. They do not provide the work result. Monitors and public registry
lookups prove cleanup.

## Research boundary

Solved observability, recovery, and distributed Agent examples moved into
these two groups. The `99_research` folder now contains five unresolved
questions only. DIST-03 has one passing cross-node restore and revision-fence
test and one enabled failure for missing cluster-wide ownership authority.

The 48 old application and adapter fixtures are no longer runnable. Their 54
profiles remain in the [archive](archive), and their source and tests remain in
Git history at commit `bd05a32`. The [research map](runtime-multi-agent-research.md)
maps each old idea to a current feature or unresolved capability.

## Validation

Run the local opt-in examples:

```shell
mix test --include example test/examples/04_runtime test/examples/05_multi_agent --seed 0
```

Run the promoted core capability tests with the commands in each profile. The
[capability ledger](research-capabilities.md) gives the combined counts. The
[gap register](runtime-multi-agent-gaps.md) separates core design questions
from adapter and application work.
