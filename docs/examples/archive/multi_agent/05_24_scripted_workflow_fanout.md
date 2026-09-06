> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Scripted Workflow Fan-Out

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_24_scripted_workflow_fanout`
- **Status:** doesn't work yet
- **Complexity level:** 5 - Large multi-Agent workflow
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Run a code-first workflow that plans phases, fans work out, verifies results, and resumes without repeating completed work.
- **User story:** As a user, I run one large audit across many items and receive one checked result with cost and completion evidence.
- **Trigger or input:** One workflow Signal contains a typed plan, bounded item list, model routes, concurrency limit, and budget.
- **Agent state:** Workflow ID, plan version, phases, child specifications, completed call cache, active children, results, verification state, budget use, and final result.
- **Actions or Flow:** One start Turn commits the plan and returns child lifecycle commands. Child results arrive as Signals. A final aggregation Flow verifies and commits the answer once.
- **External interactions:** Local scripted child Agents and fake model routes with deterministic barriers and usage records.
- **Runtime Directives or capabilities:** Spawn, stop, deliver-to-child, schedule, and worktree-like isolation commands control the child runtime.
- **Expected result:** Fan-out respects concurrency and budget, results keep input order, verified completed calls replay after restart, changed calls run again, and one final result is produced.
- **Failure cases:** Child failure, partial phase, duplicate result, budget exhaustion, route unavailable, stale plan version, failed verification, restart, cancellation, or orphaned child.
- **Jido features under pressure:** Code-first composition, child supervision, Signal correlation, bounded concurrency, durable resume, result caching, budgets, verification, and runtime observation.
- **Source framework and links:** [Pi dynamic-workflows package](https://pi.dev/packages/@quintinshaw/pi-dynamic-workflows) and [Pi subagents package](https://pi.dev/packages/pi-subagents)


## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_24_scripted_workflow_fanout/scripted_workflow_fanout.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_24_scripted_workflow_fanout/scripted_workflow_fanout_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Input-digest caching and verification work. Bounded child Actor concurrency, durable restart, and orphan cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
