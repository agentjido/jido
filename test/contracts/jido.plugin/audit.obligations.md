---
modules:
  - Jido.Plugin.Audit
  - Jido.Plugin.Audit.Record
---

## Purpose

Protect the bundled Audit Plugin's portable domain records and bounded owned
state. The component constructs and validates Audit records, declares the
Plugin-owned audit field, and reduces accepted records in order.

The component does not own generic Plugin normalization, Agent evaluation,
AgentServer commit timing, persistence, or terminal Turn summaries.

The public boundary is `Jido.Plugin.Audit.record/3`, the Audit option types,
and `Jido.Plugin.Audit.Record.validate/1`. Bounded reduction is internal
Plugin callback work. Audit uses the standard Agent Plugin declaration and
adds no Audit-specific DSL.

## Obligations

### jido.plugin.audit.I1 — Record construction

- **scope:** `Jido.Plugin.Audit.record/3`
- **must:** Build one Audit Record with the supplied event, outcome, metadata, ID, and time. Generate a UUID7 ID and current millisecond time only when those options are absent. Accept only a unique keyword list with `id`, `at`, and `metadata` options.
- **kind:** functional
- **status:** active

### jido.plugin.audit.I2 — Portable valid records

- **scope:** `Jido.Plugin.Audit.Record.validate/1`
- **must:** Accept only an Audit Record with a UUID7 ID, non-negative millisecond time, atom outcome, map metadata, and portable event and metadata terms. Return the rejected portable-term path. Reject non-record input without raising.
- **kind:** functional
- **status:** active

### jido.plugin.audit.I3 — Audit Plugin declaration

- **scope:** `Jido.Plugin.Audit.state_spec/1`, `Jido.Plugin.Audit.directives/1`
- **must:** Own one `:audit` state field that defaults to an empty record list, declare the Audit Record Directive, and accept only the Agent-owned `max_entries` option with a positive integer value.
- **kind:** functional
- **status:** active

### jido.plugin.audit.I4 — Bounded ordered reduction

- **scope:** `Jido.Plugin.Audit.reduce/2` and its internal bounded reducer
- **must:** Keep Audit Records in Directive order, ignore other Directive types, retain only the newest `max_entries` records, and trim an already oversized field even when no new record arrives.
- **kind:** ordering
- **status:** active
