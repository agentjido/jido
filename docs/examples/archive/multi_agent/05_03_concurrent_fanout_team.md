> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Concurrent Fan-Out Team

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_03_concurrent_fanout_team`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Send one task to several specialists and join their independent results.
- **User story:** As a user, I receive several perspectives without waiting for serial execution.
- **Trigger or input:** `team.fanout` Signal and correlated child result Signals.
- **Agent state:** Run ID, expected child tags, received results, failures, deadline, and joined result.
- **Actions or Flow:** A coordinator Action starts or addresses children. A join Flow reduces results when complete.
- **External interactions:** Child Actors and optional model adapters.
- **Runtime Directives or capabilities:** Spawn, emit-to-child, and timeout scheduling Directives.
- **Expected result:** The join runs once when all required replies arrive or policy closes the deadline.
- **Failure cases:** Missing reply, child error, duplicate reply, timeout, join error, or result size limit.
- **Jido features under pressure:** Concurrency, correlation, deterministic join order, partial failure, and timeout.
- **Source framework and links:** [Semantic Kernel: concurrent orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/concurrent), [Google ADK: ParallelAgent](https://adk.dev/agents/workflow-agents/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_03_concurrent_fanout_team/concurrent_fanout_team.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_03_concurrent_fanout_team/concurrent_fanout_team_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Task-based concurrent join order works. Supervised child Actor delivery, deadline handling, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
