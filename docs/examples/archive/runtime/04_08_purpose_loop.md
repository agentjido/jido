> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Finite Purpose Loop

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_08_purpose_loop`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Continue useful work through finite scheduled turns without a chat client.
- **User story:** As an operator, I start, pause, resume, and drain a bounded worker.
- **Trigger or input:** Start, tick, wake, pause, resume, and drain Signals.
- **Agent state:** Purpose, phase, generation, budget, queue progress, and last completed item.
- **Actions or Flow:** Separate Actions start, tick, enqueue, pause, resume, and drain the loop. Each tick processes at most one fixture item and returns the complete next state.
- **External interactions:** Fixture-backed queue. It can use an external work adapter in a live variant.
- **Runtime Directives or capabilities:** Scheduler Directives send the next tick only after commit and cancel work at drain.
- **Expected result:** The Actor makes progress, restores state, rejects duplicate ticks, and leaves no timer after stop.
- **Failure cases:** Duplicate or stale tick, empty queue, work error, restore error, or leaked timer.
- **Jido features under pressure:** Finite autonomous turns, Scheduler Plugin, persistence, idempotency, and cleanup.
- **Source framework and links:** [Google ADK: LoopAgent](https://adk.dev/agents/workflow-agents/), [Jido integration example](../../../../test/integration/purpose_loop/example_test.exs)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_08_purpose_loop/purpose_loop.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_08_purpose_loop/purpose_loop_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
