> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Swarm Handoffs

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_13_swarm_handoffs`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced multi-agent
- **Feature group:** multi_agent
- **Test class:** local deterministic

## Profile

- **Purpose:** Route a conversation among peers without one permanent central speaker.
- **User story:** As a user, I reach the best specialist as task needs change.
- **Trigger or input:** User message or agent handoff Signal.
- **Agent state:** Active agent, available peer capabilities, handoff count, shared Thread, and completion status.
- **Actions or Flow:** Each active agent can answer or request a validated handoff to one peer.
- **External interactions:** Peer child Actors and model adapters.
- **Runtime Directives or capabilities:** Signal delivery changes the active peer after the routing state commits.
- **Expected result:** The run ends with one final answer and no handoff cycle beyond the limit.
- **Failure cases:** Peer unavailable, circular handoff, conflicting ownership, context loss, or limit.
- **Jido features under pressure:** Decentralized routing, shared context, peer lifecycle, cycle control, and audit trail.
- **Source framework and links:** [AutoGen: Swarm tutorial](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/swarm.html)

## Best-effort implementation

- Historical source: `git show bd05a32:examples/99_research/90_legacy/multi_agent/05_13_swarm_handoffs/swarm_handoffs.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_13_swarm_handoffs/swarm_handoffs_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: Bounded peer decisions and final ownership work. Live peer Actor delivery, lifecycle, and failure handling are not implemented.

An example-scope gap is not evidence of a core Jido defect.
