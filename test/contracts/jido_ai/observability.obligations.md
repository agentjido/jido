---
modules:
  - Jido.AI.Telemetry
  - Jido.AI.Telemetry.CorrelationStore
  - Jido.AI.Telemetry.OpenTelemetry
---

## Purpose

Protect the best-effort AI observation boundary. This component owns semantic
Agent, reasoning, and tool events, correlation data, metrics, safe logging,
and optional OpenTelemetry GenAI mapping. It does not own reporter setup,
sampling, export, or the work that it observes.

## Obligations

### jido_ai.observability.I1 — Correlated AI operation identifiers

- **scope:** Agent, ReqLLM model, reasoning, and tool event bridges
- **must:** Correlate request, run, turn, Session, Thread, model request, tool call, trace, and span identifiers without using raw prompt or result content.
- **kind:** functional
- **status:** active

### jido_ai.observability.I2 — Actual tool identity

- **scope:** tool semantic events and metrics
- **must:** Report the selected tool name, description, call ID, and implementation identity, not the common graph execution wrapper.
- **kind:** functional
- **status:** active

### jido_ai.observability.I3 — Stable OpenTelemetry parentage

- **scope:** `Jido.AI.Telemetry.OpenTelemetry`
- **must:** Map Agent, model, reasoning, and tool operations to stable GenAI span names and attributes. Keep model and tool spans under the Agent span and keep work inside a tool under its tool span.
- **kind:** ordering
- **status:** active

### jido_ai.observability.I4 — OpenTelemetry remains optional

- **scope:** `Jido.AI.Telemetry.open_telemetry?/0`, `attach_open_telemetry/1`
- **must:** Work without the optional API or an active host tracer, never start an SDK, and contain bridge setup or callback failure without changing Agent work.
- **kind:** functional
- **status:** active

### jido_ai.observability.I5 — Bounded safe observation content

- **scope:** semantic event normalization and logging
- **must:** Emit fixed low-cardinality metrics and bounded scalar metadata. Exclude prompts, model output, reasoning text, tool arguments, tool results, Agent state, raw errors, and unsupported values.
- **kind:** security
- **status:** active
