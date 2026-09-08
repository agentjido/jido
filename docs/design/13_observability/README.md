> Subsystem review index. This document is pending approval.

# 13 — Observability

Current comparison: [gap analysis](gap-analysis.md).

Observability owns semantic runtime events, bounded metadata, Turn outcomes,
metrics, logs, trace propagation, and the proposed optional OpenTelemetry
bridge. Observation must not change runtime results.

Review [the observability design](observability.md) against
`lib/jido/telemetry.ex`, `lib/jido/telemetry`, `lib/jido/observe`,
`lib/jido/tracing`, and `lib/jido/debug.ex`.

[The core OpenTelemetry bridge design](opentelemetry-bridge.md) keeps
`:telemetry` as the stable semantic contract. It proposes an optional trace
bridge in core while the host owns the OpenTelemetry SDK, exporter, Collector,
sampling, and credentials. It also defines explicit context transfer across
Signals and Jido-owned Task boundaries.

Main alignment questions:

- Which semantic event names and ordering are stable?
- Where does the Turn result span stop and settlement end?
- Which metadata is safe?
- Does core keep legacy Observe and debug paths?
- Does the OpenTelemetry bridge belong in core or another package?
- How is trace context moved through Signals and Jido-owned Tasks?
