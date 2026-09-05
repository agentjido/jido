> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Cross-Framework Bridge

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `05_19_cross_framework_bridge`
- **Status:** doesn't work yet
- **Complexity level:** 5 - System
- **Feature group:** multi_agent
- **Test class:** true integration

## Profile

- **Purpose:** Call an external agent runtime as one typed Jido capability.
- **User story:** As a team, I reuse an existing external crew without giving it control of Jido state.
- **Trigger or input:** `external_agent.run` Signal with adapter ID, task, and output schema.
- **Agent state:** External run ID, request digest, status, typed result, usage, and errors.
- **Actions or Flow:** One Action calls the adapter and validates its terminal result.
- **External interactions:** External agent framework over a process or network boundary.
- **Runtime Directives or capabilities:** A Plugin can own connection, cancellation, progress, and cleanup for the external runtime.
- **Expected result:** External work returns as a typed result and Jido commits its own state once.
- **Failure cases:** Protocol mismatch, remote timeout, schema drift, duplicate completion, or cancellation failure.
- **Jido features under pressure:** Interoperability, ownership boundary, typed protocol, runtime lifecycle, and observability.
- **Source framework and links:** [CrewAI: CrewAI and LangGraph integration](https://github.com/crewAIInc/crewAI-examples/tree/main/integrations/CrewAI-LangGraph), [Pi Agent Core](https://github.com/earendil-works/pi/tree/main/packages/agent)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/multi_agent/05_19_cross_framework_bridge/cross_framework_bridge.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/multi_agent/05_19_cross_framework_bridge/cross_framework_bridge_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The terminal adapter result is validated. Managed remote progress, cancellation, reconnect, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
