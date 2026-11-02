---
modules: [Jido.Action.Validation]
---
# Shared schema validation obligations

## Purpose

Check the shared validation used by Actions and Flows. The public API remains
their validators and schema configuration. These obligations refine `ACT-001`
and `ACT-003` and retain tests for the internal validation rule.

### jido_action.validation.I1 — Validation retains the schema's data and shape rules
- **scope:** `Jido.Action.validate_params/1`, `Jido.Action.validate_output/1`, `Jido.Flow.validate_params/1`, `Jido.Flow.validate_output/1`
- **must:** Apply declared schemas at Action and Flow input/output boundaries. Keep refinements, defaults, coercion, and transforms; project normal root struct results to maps. Empty schemas still require map-shaped boundary values. Fieldless struct schemas remain valid. Accept only supported schema categories at public map boundaries. Internal scalar, lazy-schema, and shape-preserving helper cases stay implementation tests; they do not imply support in compiled Action or Flow configuration.
- **kind:** functional
- **status:** active

### jido_action.validation.I2 — Every boundary honors the declared unknown-key policy
- **scope:** `Jido.Action.validate_params/1`, `Jido.Action.validate_output/1`, `Jido.Flow.validate_params/1`, `Jido.Flow.validate_output/1`
- **must:** Honor Zoi's declared strip, preserve, strict and typed-preservation policies at direct, nested and wrapped boundaries, including collections, combinations and map sets. Do not merge stripped input fields back into parsed results. Project a parsed root struct to one plain map with all fields from that parsed struct and no added input fields.
- **kind:** functional
- **status:** active

### jido_action.validation.I3 — Schema failures retain structured public errors
- **scope:** `Jido.Action.validate_params/1`, `Jido.Action.validate_output/1`, `Jido.Flow.validate_params/1`, `Jido.Flow.validate_output/1`
- **must:** Return InvalidInputError for unsupported schemas and parse failures, with parse errors and boundary context details. At Exec, contain schema and custom-validator failures with documented types, phases, reasons, and paths without executing later work. Direct validator calls do not provide all Exec error containment.
- **kind:** functional
- **status:** active
