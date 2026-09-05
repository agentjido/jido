> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Human Approval Gate

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_06_human_approval_gate`
- **Status:** implemented
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Pause before a sensitive tool call and resume from a human decision.
- **User story:** As a reviewer, I approve, edit, or reject a proposed external action.
- **Trigger or input:** Sensitive tool proposal Signal and later approval decision Signal.
- **Agent state:** Pending request, allowed decisions, safe preview, decision, expiry, and resumed result.
- **Actions or Flow:** One Action stores a plain pending-work record. A later decision Signal selects another Action that validates the request reference and runs, edits, rejects, or expires the work.
- **External interactions:** Human interface and the protected tool. Local tests use a fake reviewer and tool.
- **Runtime Directives or capabilities:** None are required for the local form. A product can add an `Emit` notification and persistence without changing the domain transition.
- **Expected result:** The tool runs only after valid approval and only one time.
- **Failure cases:** Stale decision, edited arguments fail schema, rejection, expiry, duplicate approval, or restart.
- **Jido features under pressure:** Multi-Turn state, stale decisions, structured errors, idempotent tool calls, and one protected effect after approval.
- **Source framework and links:** [AutoGen: human in the loop](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/human-in-the-loop.html), [Sagents: HumanInTheLoop](https://sagents.hexdocs.pm/Sagents.Middleware.HumanInTheLoop.html), [CrewAI: human feedback](https://docs.crewai.com/en/learn/human-feedback-on-execution)

## Implementation result

The example does not serialize a Flow continuation. The developer owns a
small pending-work data structure and sends a later decision Signal. This is
enough for approval, edited arguments, rejection, expiry, stale decisions, and
one idempotent tool call. Durable restart support is an application persistence
choice, not a general Flow suspension requirement.

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_06_human_approval_gate/human_approval_gate.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_06_human_approval_gate/human_approval_gate_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.
