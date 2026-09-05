> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Specialist Handoff

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_09_specialist_handoff`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Transfer control between specialists based on current context.
- **User story:** As a customer, I move from triage to the correct specialist without repeating information.
- **Trigger or input:** Customer message, handoff request, specialist reply, or return Signal.
- **Agent state:** Active specialist, handoff history, shared case data, Thread, and terminal status.
- **Actions or Flow:** One routing Action validates each requested handoff and sends the next work Signal.
- **External interactions:** Specialist child Actors and optional external support tools.
- **Runtime Directives or capabilities:** Emit-to-child commands perform the handoff after state commit.
- **Expected result:** Only the active specialist can act, and every transfer has a reason.
- **Failure cases:** Unknown target, handoff cycle, missing context, child unavailable, or unauthorized transfer.
- **Jido features under pressure:** Dynamic routing, child state boundaries, shared context, cycle limit, and correlation.
- **Source framework and links:** [Semantic Kernel: handoff orchestration](https://learn.microsoft.com/en-us/semantic-kernel/frameworks/agent/agent-orchestration/handoff), [AutoGen: Swarm handoffs](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/swarm.html)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_09_specialist_handoff/specialist_handoff.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_09_specialist_handoff/specialist_handoff_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Active-owner transfer and reason checks work. Post-commit child delivery and unavailable-child handling are not implemented.

An example-scope gap is not evidence of a core Jido defect.
