> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Nested Actor Cells

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_22_nested_cells`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Reconcile a hierarchy of local controllers and workers.
- **User story:** As an operator, I manage a large task through bounded ownership regions.
- **Trigger or input:** Topology, demand, work, result, health, and reconcile Signals.
- **Agent state:** Desired hierarchy, local generations, work ownership, health summary, and cleanup status.
- **Actions or Flow:** Each controller reconciles only its direct children and reports aggregate state to its parent.
- **External interactions:** Local Actors and Signal Bus.
- **Runtime Directives or capabilities:** Hierarchical spawn, stop, parent-child Signals, Bus subscriptions, and schedules.
- **Expected result:** Failures stay inside one cell and the root can stop the full tree.
- **Failure cases:** Orphan child, stale parent, duplicate owner, cascading restart, or cleanup timeout.
- **Jido features under pressure:** Deep hierarchy, ownership, trace propagation, local reconciliation, and process count.
- **Source framework and links:** [Akka: actor hierarchy](https://doc.akka.io/libraries/akka-core/current/typed/guide/tutorial_2.html), [Google ADK: multi-agent hierarchy](https://google.github.io/adk-docs/agents/multi-agents/)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_22_nested_cells/nested_cells.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_22_nested_cells/nested_cells_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Logical hierarchy and unique worker ownership work. Real nested Actor failure isolation and complete tree stop are not implemented.

An example-scope gap is not evidence of a core Jido defect.
