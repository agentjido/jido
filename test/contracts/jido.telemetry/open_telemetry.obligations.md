---
modules:
  - Jido.Telemetry.OpenTelemetry
  - Jido.Telemetry.OpenTelemetry.Span
---

## Purpose

Protect the optional OpenTelemetry bridge at the execution layer. The host
application owns SDK startup, sampling, and export.

## Obligations

### jido.telemetry.open_telemetry.I1 — Optional span and carrier mapping

- **scope:** `Jido.Telemetry.OpenTelemetry` and its semantic event integration
- **must:** Activate only when the API is available, configuration permits it, and the host tracer is active. Map normalized semantic spans and points to bounded names and scalar attributes. Keep parents and links, map W3C carriers, and set error status without raw exception data. End each span once and restore the caller context. Keep Turn settlement and effects point spans in their Turn trace. Leave SDK startup and configuration to the host.
- **kind:** functional
- **status:** active

### jido.telemetry.open_telemetry.I2 — Bridge fault containment

- **scope:** bridge callbacks, options, carriers, and context transitions
- **must:** Contain optional bridge faults. Preserve valid Telemetry events and the observed result or fault. Restore the caller context after a callback failure.
- **kind:** ordering
- **status:** active
