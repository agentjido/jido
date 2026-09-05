> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Embedded Agent SDK

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_19_embedded_agent_sdk`
- **Status:** doesn't work yet
- **Complexity level:** 4 - Advanced runtime
- **Feature group:** runtime
- **Test class:** true integration

## Profile

- **Purpose:** Embed one Jido-backed agent in another application through a stable session API.
- **User story:** As an application developer, I start a session, send input, observe events, cancel work, and restore history.
- **Trigger or input:** SDK start, prompt, steer, cancel, resume, or close request.
- **Agent state:** Session ID, Thread reference, selected capabilities, terminal outcome, and usage summary.
- **Actions or Flow:** Each prompt becomes one Signal and selects one Action or Flow. Steering and cancellation become explicit later Signals or runtime controls.
- **External interactions:** Host application, model providers, and host-supplied tools.
- **Runtime Directives or capabilities:** Session lifecycle, subscriptions, cancellation, and cleanup need a small public SDK surface.
- **Expected result:** The host receives typed events and one terminal result without direct access to Actor process internals.
- **Failure cases:** Host disconnect, duplicate request, incompatible tool schema, cancellation race, restore error, or leaked subscription.
- **Jido features under pressure:** Stable embedding API, session identity, event stream, cancellation, restore, and capability injection.
- **Source framework and links:** [Pi: Agent Core](https://github.com/earendil-works/pi/tree/main/packages/agent), [Pi: OpenClaw SDK integration reference](https://github.com/openclaw/openclaw)

## Best-effort implementation

- Historical source: `git show bd05a32:lib/examples/99_research/90_legacy/runtime/04_19_embedded_agent_sdk/embedded_agent_sdk.ex`
- Historical tests: `git show bd05a32:test/examples/99_research/90_legacy/runtime/04_19_embedded_agent_sdk/embedded_agent_sdk_test.exs`

The local spike passes its mock-only tests. The complete profile **doesn't work yet**.

- Gap type: example scope.
- Remaining work: The facade proves typed prompt results. Stable subscriptions, steering, restore, cancellation, and cleanup are not implemented.

An example-scope gap is not evidence of a core Jido defect.
