> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Elastic Actor Group

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_20_elastic_group`
- **Status:** implemented
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Scale workers from measured demand and reclaim failed work.
- **User story:** As an operator, I keep throughput within limits without duplicate results or leaked workers.
- **Trigger or input:** Demand sample, work, lease, result, worker exit, drain, and scale Signals.
- **Agent state:** Desired worker count, logical workers, demand history, leases, results, cooldown, and phase.
- **Actions or Flow:** Finite Actions measure, decide scale, reconcile workers, and settle work.
- **External interactions:** Local supervised Actors and Signal Bus.
- **Runtime Directives or capabilities:** Spawn, stop, emit, monitor, subscription, and scheduled observation commands.
- **Expected result:** The group scales from 2 to 10 and back to 2, reclaims failed leases, and cleans up.
- **Failure cases:** The test covers one worker crash, work reclaim, one duplicate environment result, scale down, and cleanup. It does not cover controller restart, an expired drain deadline, or repeated start and stop.
- **Jido features under pressure:** Dynamic topology, hysteresis, child recovery, work ownership, and large state.
- **Source framework and links:** [Akka: cluster-aware routers](https://doc.akka.io/libraries/akka-core/current/typed/cluster.html), [Jido integration example](../../../../examples/08_applications/08_10_elastic_group/elastic_group.ex)

## Next pressure

Add controller restore, drain deadline, idempotent lifecycle, and sustained
demand-threshold cases.

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_20_elastic_group/elastic_group.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_20_elastic_group/elastic_group_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
