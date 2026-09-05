> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Agent-to-Agent Protocol

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_15_agent_to_agent_protocol`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** true integration

## Profile

- **Purpose:** Exchange typed tasks and results with agents outside the Jido runtime.
- **User story:** As an agent platform, I delegate a task to a remote agent and track its lifecycle.
- **Trigger or input:** Remote task request, progress, artifact, completion, cancellation, or error event.
- **Agent state:** Remote agent identity, task ID, protocol state, artifacts, and terminal result.
- **Actions or Flow:** One Action maps each protocol event to Jido state and sends follow-up work through an adapter.
- **External interactions:** A2A or another agent protocol over the network.
- **Runtime Directives or capabilities:** Jido needs a protocol Plugin for discovery, auth, transport, streaming events, and cancellation.
- **Expected result:** Remote task state is correlated, authenticated, and resumable.
- **Failure cases:** Protocol mismatch, identity failure, lost connection, duplicate event, or remote cancellation.
- **Jido features under pressure:** No current A2A Plugin, dynamic remote capabilities, security, and durable task state.
- **Source framework and links:** [Google ADK: A2A](https://google.github.io/adk-docs/a2a/)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_15_agent_to_agent_protocol/agent_to_agent_protocol.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_15_agent_to_agent_protocol/agent_to_agent_protocol_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The typed remote-event reducer works. A2A discovery, transport, authentication, reconnect, and cancellation are not implemented.

An example-scope gap is not evidence of a core Jido defect.
