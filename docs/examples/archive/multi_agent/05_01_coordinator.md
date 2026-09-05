> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Coordinator and Worker

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_01_coordinator`
- **Status:** implemented
- **Complexity level:** 3 - Multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Delegate one job to a child Actor and correlate its reply or timeout.
- **User story:** As a caller, I receive one terminal result from delegated work.
- **Trigger or input:** A job Signal, child reply Signal, or scheduled timeout Signal.
- **Agent state:** Pending job ID, child tag, phase, result, and terminal reason.
- **Actions or Flow:** One Flow records delegation intent and returns child lifecycle and work commands.
- **External interactions:** Local child Actor.
- **Runtime Directives or capabilities:** `SpawnActor`, `EmitToChild`, and Scheduler Directives run after commit.
- **Expected result:** The first Flow turn commits one delegation and one Thread entry before it starts the child and sends work. The test then observes one handled task, one reply, one timeout, and one child-start event.
- **Failure cases:** Child start failure, no reply, duplicate reply, timeout race, child crash, and late reply are not covered by the current test.
- **Jido features under pressure:** Child lifecycle, correlation, scheduling, stale Signals, and one commit per turn.
- **Source framework and links:** [Semantic Kernel: handoff orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/handoff), [Jido integration example](../../../../test/integration/coordinator/example_test.exs)

## Next pressure

Make an early reply cancel or supersede its timeout. Prove that one terminal
result wins and a late reply cannot change it.

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_01_coordinator/coordinator.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_01_coordinator/coordinator_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
