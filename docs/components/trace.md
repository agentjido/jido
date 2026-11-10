---
title: Jido.Trace component
status: current
last-reviewed: 2026-11-10
---

# Jido.Trace component

`Jido.Trace` owns one validated W3C trace value and its propagation through the
Jido runtime.

## Public contract

The component has two proof surfaces.

### Trace value

| Surface | Public operations |
| --- | --- |
| Creation | `new/0,1`, `child/1,2`, `with_causation/2` |
| W3C carrier | `from_traceparent/1,2`, `to_traceparent/1` |
| Validation | `schema/0`, `valid?/1` |
| Projection | `telemetry_context/1`, `metadata/1` |

The value contains trace and span IDs, trace flags, optional tracestate,
optional parent span, and optional application causation ID.

### Trace context

`Jido.Trace.Context` starts a Turn context, stores process-local context,
captures it for task transfer, restores it around work, propagates it to a
Signal, and clears local context. Its exports are runtime-facing. Most are
marked `@doc false`.

## Architectural boundary

### Owns

- Valid W3C version-00 traceparent and tracestate values.
- Root and child span identity.
- Application causation metadata.
- Process-local capture and restoration.
- Transfer to outbound Signals.
- The bridge between Jido trace context and optional OpenTelemetry context.

### Does not own

- Signal storage of trace data. `Jido.Signal.Context` owns that attachment.
- Telemetry event schemas, metrics, logs, sampling, export, or SDK startup.
- AgentServer Turn behavior or Plugin scheduling behavior.

### Dependency position

The current component crosses two Reach layers:

- `Jido.Trace` is in `primitives`.
- `Jido.Trace.Context` is in `live_runtime` because it uses Signal and
  OpenTelemetry runtime context.

This split is intentional in current code, but it conflicts with a rule that
requires every Covenant component to own modules from only one Reach layer.

## Covenant and evidence

Trace has no focused active Covenant component. `jido.telemetry` currently owns
the Trace modules and includes two Trace obligations:

- W3C Signal trace values.
- Process and task trace context.

Tests exist in `test/jido/trace_test.exs`, telemetry trace tests, AgentServer
effect tests, scheduler tests, and Signal property tests.

## Boundary review

Trace is one component with value and context proof surfaces. It is not part of
Telemetry. The current Covenant owner must eventually represent the Trace
component without violating the Reach ownership rule.

## Sources

- [`Jido.Trace`](../../lib/jido/trace.ex)
- [`Jido.Trace.Context`](../../lib/jido/trace/context.ex)
- [Telemetry Covenant obligations](../../test/contracts/jido/telemetry.obligations.md)
- [Reach layers](../../.reach.exs)

