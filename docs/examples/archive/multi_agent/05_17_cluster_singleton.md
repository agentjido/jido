> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Cluster Singleton

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_17_cluster_singleton`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** true integration

## Profile

- **Purpose:** Keep one logical coordinator active across several BEAM nodes.
- **User story:** As an operator, I keep one scheduler or leader available after node failure.
- **Trigger or input:** Cluster membership, lease, leadership, and client command Signals.
- **Agent state:** Logical role ID, generation, leader epoch, command ledger, and handoff status.
- **Actions or Flow:** One coordinator Action accepts commands only when its lease epoch is current.
- **External interactions:** Distributed membership, lease, and registry services.
- **Runtime Directives or capabilities:** Jido needs cluster-aware placement, fencing, handoff, and remote Signal delivery capabilities.
- **Expected result:** At most one valid leader epoch accepts writes and a new leader recovers state.
- **Failure cases:** Network partition, stale leader, lease loss, split brain, restore error, or remote timeout.
- **Jido features under pressure:** No current public distributed Actor placement and fencing contract.
- **Source framework and links:** [Akka: Cluster Singleton](https://doc.akka.io/libraries/akka-core/current/typed/cluster-singleton.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_17_cluster_singleton/cluster_singleton.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_17_cluster_singleton/cluster_singleton_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: Local leader-epoch validation works. Cluster placement, leases, failover, and distributed fencing are missing.

An example-scope gap is not evidence of a core Jido defect.
