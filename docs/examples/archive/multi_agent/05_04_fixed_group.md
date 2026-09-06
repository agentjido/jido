> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Fixed Actor Group

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_04_fixed_group`
- **Status:** implemented
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Run a fixed controller, environment, and worker group over a Signal Bus.
- **User story:** As an operator, I start a known group, route work, and stop all members cleanly.
- **Trigger or input:** Group start, work, result, health, and stop Signals.
- **Agent state:** Desired logical members, work ownership, results, and group phase.
- **Actions or Flow:** Finite Actions reconcile topology, assign work, and accept correlated results.
- **External interactions:** Local supervised child Actors and Signal Bus.
- **Runtime Directives or capabilities:** Child lifecycle, Bus subscription, and Signal delivery Directives.
- **Expected result:** The test starts one environment and three stable workers, distributes nine tasks, replaces one killed worker with the same logical ID, and stops all Actor children.
- **Failure cases:** Missing-member reconciliation, repeated start, duplicate result, and subscription cleanup are not covered by the current test.
- **Jido features under pressure:** Desired topology, child Actors, Bus semantics, stable IDs, and cleanup.
- **Source framework and links:** [AutoGen: teams](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html), [Jido integration example](../../../../examples/08_applications/08_09_fixed_group/fixed_group.ex)

## Next pressure

Add idempotent start and stop, explicit subscription cleanup, duplicate result,
and controller restart cases.

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_04_fixed_group/fixed_group.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_04_fixed_group/fixed_group_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
