# ADR 0013 — Align Telemetry and Trace proof with Reach

- **Status** Accepted
- **Date** 2026-11-19

## Context

Decision D13 gives W3C values and context propagation to Trace. The original
Telemetry Covenant profile covered modules from three Reach layers.

## Decision

Use `jido.telemetry` for live-runtime semantic events, metrics, logging, and
normalization. Use `jido.telemetry.open_telemetry` for the optional span and
carrier adapter at the execution layer. Its integration tests cover both
span mapping and context restoration.

Use `jido.trace` for W3C values in the primitives layer and
`jido.trace.context` for process and task propagation in the execution layer.
These profiles cover two parts of the same Trace component.

## Consequences

Each profile assigns proof ownership within one Reach layer. Feature layers
continue to emit their own events. The host application owns SDK startup,
sampling, and export.

## References

- [Trace boundary decision D13](../../components.md#d13-trace-boundary)
- [Module dependency map](../architecture/module-dependency-map.md#telemetry)
- [Covenant component profiles](../../test/contracts/README.md)
