> Current acceptance runs, 2026-09-05: [ten feature probes](feature-acceptance-results.md)
> and [three live-upgrade examples](live-upgrade-results.md) have 34 passing
> checks and 11 failing checks across nine proposed core features. All 45 checks
> are enabled. These reports supersede older research counts for these targets.

> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the migration guide](../../guides/migration.md) for current API changes.

# Jido capability research ladder

Date: **2026-09-04**. The goal is to prove Agents that can explain and recover
unfinished work, including a parent that starts and manages a child on another
Erlang node.

The package examples teach Jido capabilities. A Slack, browser, MCP, email, or
media connection is an adapter concern. Provider-neutral inputs, resources,
workers, and sinks test the Jido runtime boundary.

## Proven foundation

The five main groups have **43 feature fixtures and 254 passing tests**:

| Group | Fixtures | Passing tests | Skips |
| --- | ---: | ---: | ---: |
| Basic | 5 | 22 | 0 |
| Workflow | 9 | 35 | 0 |
| LLM | 10 | 66 | 0 |
| Runtime | 13 | 93 | 0 |
| Multi-agent | 6 | 38 | 0 |

The 170 opt-in example tests use real Jido execution with controlled local
model and service inputs. The promoted Runtime and Multi-agent capabilities
add 84 focused core tests. Live provider compatibility is outside this proof.

## Promoted capabilities

Seven solved targets now belong to the main learning sequence:

| ID | Current example | Proof |
| --- | --- | --- |
| OBS-01 | [Agent Observation](../../examples/04_runtime/04_09_agent_observation/turn_observation.ex) | Lifecycle, Turn, commit, cancellation, and terminal outcomes; 9 tests |
| OBS-02 | [Causal Trace](../../examples/04_runtime/04_10_causal_trace/causal_trace.ex) | Local and remote creation causes through retry, restore, and restart; 12 tests |
| REC-01 | [Recoverable Delivery](../../examples/04_runtime/04_11_recoverable_delivery/recoverable_delivery.ex) | Saved effect intent, restart, duplicate delivery, and committed confirmation; 11 tests |
| REC-02 | [Pending Job Recovery](../../examples/04_runtime/04_12_pending_job_recovery/pending_job_recovery.ex) | Approval, attempt identity, retry, cancellation, and restore; 7 tests |
| REC-03 | [Durable Scheduling](../../examples/04_runtime/04_13_durable_scheduling/scheduled_occurrence_recovery.ex) | Occurrence identity, saved work, retry, acknowledgement, and skip policy; 25 tests |
| DIST-01 | [Remote Child](../../examples/05_multi_agent/05_05_remote_child/remote_child.ex) | Selected-node placement, ownership, Signal exchange, and cleanup; 16 tests |
| DIST-02 | [Remote Lifecycle](../../examples/05_multi_agent/05_06_remote_lifecycle/remote_lifecycle.ex) | Disconnect, node loss, parent loss, and replacement; 4 tests |

Each profile in the [catalog](catalog.md) gives its focused command. The result
reports for [OBS-02](obs-02-results.md), [REC-03](rec-03-results.md),
[DIST-01](dist-01-results.md), and [DIST-02](dist-02-results.md) give the detailed
runtime limits.

## Research queue and retained regressions

Five scope questions remain under `99_research`. The three persistence
boundaries are fixed and keep their enabled regression tests:

| ID | Queue item | Required proof |
| --- | --- | --- |
| OBS-03 | [Progress observation](../../examples/99_research/99_01_progress_observation/README.md) | Public progress, waiting reasons, interruption, and bounded consumers |
| DIST-03 | [Distributed authority](../../examples/99_research/99_02_distributed_authority/README.md) | One cluster owner for one stable Agent identity |
| CTRL-01 | [Input and resource lifecycle](../../examples/99_research/99_03_input_resource_lifecycle/README.md) | Typed ingress, reconnect, cancellation, expiry, and cleanup |
| CTRL-02 | [Handoff and reconciliation](../../examples/99_research/99_04_handoff_reconciliation/README.md) | Acknowledged ownership transfer and desired worker reconciliation |
| CTRL-03 | [Capacity, deadlines, and cleanup](../../examples/99_research/99_05_capacity_deadlines_cleanup/README.md) | Bounded admission, deadline behavior, and complete large-tree cleanup |
| PERSIST-01 | [Checkpoint identity](../../examples/99_research/99_06_checkpoint_identity/README.md) | Reject a loaded Agent whose identity differs from the requested identity |
| PERSIST-02 | [Checkpoint portability](../../examples/99_research/99_07_checkpoint_portability/README.md) | Reject process-local values supplied by storage |
| PERSIST-03 | [Indeterminate write](../../examples/99_research/99_08_indeterminate_write/README.md) | Prevent further Action work after an unknown write result |

The matching test notes are under
[`test/examples/99_research`](../../test/examples/99_research/README.md). They
define acceptance criteria and do not use skipped placeholder tests.

DIST-03 has one passing proof for cross-node restore and stale revision fencing.
Its second enabled test shows the current gap: two live nodes can start the same
logical Agent before either activation writes. A revision check is not a
cluster ownership claim. Work pauses at this core design boundary.

The three persistence examples have six passing controls and three enabled
acceptance failures. They use an application-owned in-memory byte adapter.
They test core validation and admission; database integration and VM recovery
remain outside this work. See the [persistence boundary results](persistence-boundary-results.md).

## Remote child requirement

The remote child proof uses two Erlang VMs on one machine. The parent requests
a child with `SpawnAgent.node`. The test fails if the child starts locally. It
checks the remote PID, remote execution, parent and child identity, correlated
Signals, unavailable nodes, startup failure, child stop, and parent cleanup.

The [runnable example](../../examples/05_multi_agent/05_05_remote_child/demo.exs)
uses OTP `peer` with a private cookie and an independent standard IO control
channel:

```shell
mix run examples/05_multi_agent/05_05_remote_child/demo.exs
```

This proves Erlang distribution between two local Agent nodes. It does not
prove multi-host deployment, cluster ownership authority, or automatic
failover. The [remote-child contract](../design/remote-owned-children.md)
defines the implemented boundary.

## Historical examples

All 54 original Runtime and Multi-agent profiles remain under
[`docs/examples/archive`](archive). The 48 application and adapter fixtures are
not runnable source. Their source and tests remain available in Git history at
commit `bd05a32`.

The [complete research map](runtime-multi-agent-research.md) maps each old idea
to a current feature or an unresolved capability. For example:

| Old idea | Current Jido question |
| --- | --- |
| Slack Channel Agent / Support Email Agent | Stable input identity and recoverable post-commit output, REC-01 |
| Browser Agent / Sandbox / MCP Client | Owned resource, typed ingress, reconnect, cancellation, and cleanup, CTRL-01 |
| Streaming Chat / Voice Assistant / Embedded SDK | Progress, interruption, terminal results, and bounded consumers, OBS-03 |
| Cluster Sharding / Singleton | Remote lifecycle, then stable identity and cluster authority, DIST-01 through DIST-03 |
| Large Review Tree / Swarm Control | Real Agents, bounded queues, deadlines, and monitored cleanup, CTRL-03 |

Do not add skipped `flunk` tests for these plans. Add a real enabled acceptance
test when work starts. Promote an item only after its public SDK path passes.
