> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Subagent Delegation

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_10_subagent_delegation`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Run a specialist with isolated conversation state and return only its result.
- **User story:** As a parent agent, I delegate a focused task without filling my own context.
- **Trigger or input:** A task Signal with specialist type, instructions, and result schema.
- **Agent state:** Delegation ID, specialist type, status, result summary, and resource use.
- **Actions or Flow:** A parent Action starts a child, sends the task, and handles the correlated final reply later.
- **External interactions:** Child Actor and optional model or tools.
- **Runtime Directives or capabilities:** SpawnActor, EmitToChild, EmitToParent, StopChild, and timeout commands.
- **Expected result:** The parent receives one typed result and the child is cleaned up.
- **Failure cases:** Unknown specialist, child start error, timeout, approval needed, bad result, or cleanup failure.
- **Jido features under pressure:** Context isolation, child lifecycle, correlation, nested approval, and token use.
- **Source framework and links:** [Sagents: SubAgent middleware](https://sagents.hexdocs.pm/Sagents.Middleware.SubAgent.html), [Pi: subagent extension](https://github.com/earendil-works/pi/tree/main/packages/coding-agent/examples/extensions/subagent)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_10_subagent_delegation/subagent_delegation.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_10_subagent_delegation/subagent_delegation_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: An isolated adapter returns only a typed summary. Spawn, reply correlation, deadline, and child cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
