> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Agent Live Debugger

> Research profile retained on 2026-09-04. The requirements below describe the
> original domain scenario. See the [current assessment](../../runtime-multi-agent-research.md)
> and [gap register](../../runtime-multi-agent-gaps.md) before treating a gap as an SDK defect.

- **ID:** `04_03_agent_live_debugger`
- **Status:** implemented
- **Complexity level:** 3 - Runtime
- **Feature group:** runtime
- **Test class:** local deterministic

## Profile

- **Purpose:** Inspect Actor state, active turn metadata, Plugin state, children, and recent outcomes.
- **User story:** As a developer, I understand why an agent is waiting, failed, or changed state.
- **Trigger or input:** Debug snapshot request or subscribed lifecycle event.
- **Agent state:** The observed Actor does not store debugger view state. The debugger keeps safe references and filters.
- **Actions or Flow:** A debugger Action reads public inspection data and creates a redacted snapshot.
- **External interactions:** Local Actor Server inspection and optional web UI.
- **Runtime Directives or capabilities:** A debug input capability subscribes to bounded lifecycle events. It does not alter the observed Actor.
- **Expected result:** Snapshots show stable IDs and statuses without exposing Signal payloads, Plugin secrets, or transient context.
- **Failure cases:** Actor exits during read, stale reference, event overload, unsafe field, inaccessible child, or UI disconnect.
- **Jido features under pressure:** Public inspection API, redaction, telemetry correlation, bounded subscriptions, and runtime isolation.
- **Source framework and links:** [Sagents: Live Debugger](https://github.com/sagents-ai/sagents_live_debugger), [Sagents: LiveView helpers](https://hexdocs.pm/sagents/Mix.Tasks.Sagents.Gen.LiveHelpers.html)

## Best-effort implementation

- [Code](../../../../examples/04_runtime/04_05_runtime_inspection/agent_live_debugger.ex)
- [Tests](../../../../test/examples/04_runtime/04_05_runtime_inspection/agent_live_debugger_test.exs)

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

Current feature: [Runtime Inspection](../../profiles/04_runtime/04_05_runtime_inspection.md).
