> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Sequential Specialist Team

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_02_sequential_specialist_team`
- **Status:** doesn't work yet
- **Complexity level:** 3 - Multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Pass one work product through several specialist Actors in fixed order.
- **User story:** As a user, I receive output that was researched, drafted, and reviewed.
- **Trigger or input:** `team.run` Signal with task and ordered role list.
- **Agent state:** Run ID, current role, work product versions, feedback, and terminal status.
- **Actions or Flow:** A coordinator Action sends work to one child at a time and handles each reply in a later turn.
- **External interactions:** Child Actors. Optional model calls stay inside specialist Actions.
- **Runtime Directives or capabilities:** Spawn children and emit work or reply Signals after each commit.
- **Expected result:** Every stage receives the prior stage output and the order is traceable.
- **Failure cases:** Child unavailable, bad output schema, timeout, duplicate reply, or stage limit.
- **Jido features under pressure:** Sequential orchestration across turns, child correlation, state growth, and timeouts.
- **Source framework and links:** [Semantic Kernel: sequential orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/sequential), [Google ADK: SequentialAgent](https://adk.dev/agents/workflow-agents/)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_02_sequential_specialist_team/sequential_specialist_team.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_02_sequential_specialist_team/sequential_specialist_team_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Ordered specialist transformations work. Separate child Actor Turns, correlated replies, and lifecycle cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
