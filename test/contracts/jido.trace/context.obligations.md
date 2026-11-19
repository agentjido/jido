---
modules:
  - Jido.Trace.Context
  - Jido.Trace.Context.Captured
---

## Purpose

Protect process and task propagation of the Trace value at the execution layer.

## Obligations

### jido.trace.context.I1 — Process and task trace context

- **scope:** `Jido.Trace.Context`
- **must:** Start one local Turn context from a valid incoming Signal parent or a new root. Capture and restore Jido and OpenTelemetry contexts across task boundaries. Restore the caller context after success or failure. Propagate the active context and explicit cause to an outbound Signal. Clear all locally installed context.
- **kind:** ordering
- **status:** active
