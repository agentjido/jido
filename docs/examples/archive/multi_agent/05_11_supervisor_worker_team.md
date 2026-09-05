> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Supervisor and Worker Team

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_11_supervisor_worker_team`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Let a supervisor select and join specialist work.
- **User story:** As a user, I give one goal and a supervisor assigns its parts to the right workers.
- **Trigger or input:** Goal Signal, worker result Signal, or supervisor review Signal.
- **Agent state:** Plan, worker capabilities, assignments, results, review notes, and final output.
- **Actions or Flow:** The supervisor Flow plans, dispatches bounded work, reviews results, and requests corrections.
- **External interactions:** Specialist child Actors and optional model calls.
- **Runtime Directives or capabilities:** Spawn, emit-to-child, timeout, and stop-child commands.
- **Expected result:** Each assignment has one owner and the supervisor produces one final result.
- **Failure cases:** Bad decomposition, missing capability, worker error, review loop, or budget limit.
- **Jido features under pressure:** Dynamic delegation, capability data, nested loops, child lifecycle, and cleanup.
- **Source framework and links:** [LangGraph: agent supervisor](https://langchain-ai.github.io/langgraph/tutorials/multi_agent/agent_supervisor/), [Mastra: multi-agent workflow](https://mastra.ai/en/examples/agents/multi-agent-workflow)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_11_supervisor_worker_team/supervisor_worker_team.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_11_supervisor_worker_team/supervisor_worker_team_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Assignment ownership and review work. Child Actor dispatch, correction loops, deadlines, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
