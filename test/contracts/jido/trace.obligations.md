---
modules:
  - Jido.Trace
---

## Purpose

Protect the primitive W3C Trace value. Signal carrier tests check how the
value crosses the Signal boundary.

## Obligations

### jido.trace.I1 — W3C Trace values and Signal carriers

- **scope:** `Jido.Trace` values and their use by `Jido.Signal.Context`
- **must:** Create valid W3C roots and children. Retain trace flags, tracestate, parent identifiers, and explicit causation. Use the Signal context for the carrier. Remove old private trace fields when writing. Reject malformed and legacy-only values. Expose only validated identifiers to Telemetry.
- **kind:** functional
- **status:** active
