---
modules:
  - Jido.Telemetry
  - Jido.Telemetry.AgentServer
  - Jido.Telemetry.Semantic
  - Jido.Telemetry.Persistence
---

## Purpose

Protect the live-runtime observation boundary. The public facade provides
`Jido.Telemetry.metrics/0` and `Jido.Telemetry.open_telemetry?/0`. The
`:debug` instance option and the internal `Jido.Telemetry.set_debug/2`
entry point change persistence operation logging for one instance. Turn and
effects logs use the global mode.

This component owns the metric catalog, core semantic events, field
normalization, bounded logs, and debug overrides.

It does not own the AgentServer or persistence operations that emit events,
host reporter configuration, OpenTelemetry SDK startup, sampling, export, or
durable audit records.

## Obligations

### jido.telemetry.I1 — Fixed low-cardinality metric catalog

- **scope:** `Jido.Telemetry.metrics/0`
- **must:** Return one stable metric definition for each supported span ending and point event. Give only span endings duration summaries, convert their native duration to milliseconds, and use only fixed status, stage, operation, and persistence-reason tags. Do not use runtime identities as metric tags.
- **kind:** functional
- **status:** active

### jido.telemetry.I2 — Safe semantic fields

- **scope:** semantic metadata and measurement normalization
- **must:** Publish schema version 1 and only approved scalar metadata and integer measurements. Bound identifier sizes and fixed vocabularies. Drop private values, invalid UTF-8, raw errors, state, payloads, unsupported numbers, unknown fields, and malformed observation input before Telemetry, logs, or tracing can observe them.
- **kind:** security
- **status:** active

### jido.telemetry.I3 — One semantic operation lifecycle

- **scope:** semantic spans, points, result classification, persistence observation
- **must:** Emit start and at most one terminal event for each valid span name. Include nonnegative duration, classify supported return results without their payloads, return the observed result unchanged, and re-raise an observed fault after one exception event. A failing result-measurement projection must not change that result. Emit point events with event time. Persistence observation must add only safe identity, operation, reason, and revision fields.
- **kind:** ordering
- **status:** active

### jido.telemetry.I4 — Bounded logs and instance debug overrides

- **scope:** default semantic handler, log configuration, per-instance Telemetry debug state
- **must:** Attach the default semantic log handler idempotently. Keep logging off by default. Support errors, interesting, and all modes with normalized fields. Escape caller-controlled C0 and C1 controls and Unicode line separators, keep each binary value on one physical line, and limit its rendered value to 128 bytes. Let a valid per-instance debug level override the global log mode only for events in that instance scope. Keep debug state isolated by instance and treat absent or malformed state as off.
- **kind:** functional
- **status:** active

### jido.telemetry.I8 — Observation failure containment

- **scope:** semantic emission and logging
- **must:** Contain faults from logging, Telemetry handlers, and result-measurement callbacks. Treat malformed configuration, metadata, measurements, options, carriers, and event names as absent observation data. Preserve the observed result or fault and restore installed context.
- **kind:** functional
- **status:** active
