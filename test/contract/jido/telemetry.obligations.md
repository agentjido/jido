---
modules:
  - Jido.Debug
  - Jido.Telemetry
  - Jido.Telemetry.Semantic
  - Jido.Telemetry.OpenTelemetry
  - Jido.Telemetry.Persistence
  - Jido.Tracing.Context
  - Jido.Tracing.Trace
---

## Purpose

Protect Jido observation values and adapters. This component owns the fixed
metric catalog, semantic event lifecycle, safe fields, bounded logs, instance
debug overrides, W3C trace context, and optional OpenTelemetry mapping.

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
- **must:** Publish schema version 1 and only approved scalar metadata and integer measurements. Bound identifier sizes and fixed vocabularies. Drop private values, invalid UTF-8, raw errors, state, payloads, unsupported numbers, and unknown fields before Telemetry, logs, or tracing can observe them.
- **kind:** security
- **status:** active

### jido.telemetry.I3 — One semantic operation lifecycle

- **scope:** semantic spans, points, result classification, persistence observation
- **must:** Emit start and at most one terminal event for each span. Include nonnegative duration, classify supported return results without their payloads, return the observed result unchanged, and re-raise an observed fault after one exception event. Emit point events with event time. Persistence observation must add only safe identity, operation, reason, and revision fields.
- **kind:** ordering
- **status:** active

### jido.telemetry.I4 — Bounded logs and instance debug overrides

- **scope:** default semantic handler, log configuration, `Jido.Debug`
- **must:** Attach the default semantic log handler idempotently. Keep logging off by default. Support errors, interesting, and all modes with bounded normalized fields. Let a valid per-instance debug level override the global log mode only for events in that instance scope. Keep debug state isolated by instance and treat absent or malformed state as off.
- **kind:** functional
- **status:** active

### jido.telemetry.I5 — W3C Signal trace values

- **scope:** `Jido.Tracing.Trace`
- **must:** Create valid W3C roots and children, retain trace flags and tracestate, record explicit parent and causation identifiers, and use `Jido.Signal.Trace` as the Signal carrier. Remove old private trace fields when writing. Reject malformed or legacy-only values and expose only validated identifiers to telemetry.
- **kind:** functional
- **status:** active

### jido.telemetry.I6 — Process and task trace context

- **scope:** `Jido.Tracing.Context`
- **must:** Start one local Turn context from a valid incoming Signal parent or a new root. Capture and restore Jido and OpenTelemetry contexts across task boundaries. Restore the caller context after success or failure. Propagate the active context and explicit cause to an outbound Signal. Clear all locally installed context.
- **kind:** ordering
- **status:** active

### jido.telemetry.I7 — Optional OpenTelemetry mapping

- **scope:** `Jido.Telemetry.OpenTelemetry`
- **must:** Activate only when the API is available, configuration permits it, and the host tracer is not a no-op tracer. Map normalized semantic spans and points to bounded internal span names and scalar attributes. Preserve parents and links, map W3C carriers, set error status without raw exception data, end each mapped span once, and restore caller context. Do not start or configure an SDK.
- **kind:** functional
- **status:** active

### jido.telemetry.I8 — Observation failure containment

- **scope:** semantic emission, logging, trace adapters, and optional bridge callbacks
- **must:** Contain logging, Telemetry handler, malformed configuration, carrier, event-name, and OpenTelemetry callback faults. Observation failure must not change the observed result, suppress the semantic event when the optional bridge fails, or leak an installed context.
- **kind:** functional
- **status:** active
