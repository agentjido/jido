> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Cluster-Sharded Entities

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_16_cluster_sharded_entities`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** true integration

## Profile

- **Purpose:** Place many logical Actors across nodes by stable entity ID.
- **User story:** As an operator, I address any entity without knowing its physical node.
- **Trigger or input:** Remote entity Signal, shard movement, node change, or passivation event.
- **Agent state:** Entity domain state and durable generation. Physical location stays outside domain state.
- **Actions or Flow:** Each entity handles one Signal with one Action or Flow.
- **External interactions:** Distributed registry, transport, shard coordinator, and persistence.
- **Runtime Directives or capabilities:** Jido needs remote routing, shard placement, passivation, rebalance, and fencing capabilities.
- **Expected result:** One logical entity processes each command under one current ownership epoch.
- **Failure cases:** Rebalance race, duplicate entity, partition, buffer overflow, restore error, or stale route.
- **Jido features under pressure:** No current cluster sharding contract, stable refs across nodes, delivery, and ownership.
- **Source framework and links:** [Akka: Cluster Sharding](https://doc.akka.io/libraries/akka-core/current/typed/cluster-sharding.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_16_cluster_sharded_entities/cluster_sharded_entities.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_16_cluster_sharded_entities/cluster_sharded_entities_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: SDK contract.
- Remaining work: Local epoch validation works. Distributed routing, placement, rebalance, passivation, and authoritative fencing are missing.

An example-scope gap is not evidence of a core Jido defect.
