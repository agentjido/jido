---
modules:
  - Jido.Thread
  - Jido.Thread.Document
  - Jido.Thread.Entry
---

## Purpose

Keep an immutable, portable history of interactions in append order.

## Obligations

### jido.thread.I1 — Ordered portable history

- **scope:** `Jido.Thread` and `Jido.Thread.Entry`
- **must:** Assign contiguous sequence numbers on append. Keep the supplied
  timestamps and kinds. Round-trip valid Thread and Entry values through
  their portable maps. Keep revision and entry count equal to the number of
  entries.
- **kind:** persisted-format
- **status:** active

### jido.thread.I2 — Invalid history rejection

- **scope:** Thread and Entry validation, append, encode, and decode
- **must:** Reject conflicting field aliases, invalid fields, process-local
  terms, and malformed history with the error form of the operation. Apply
  defaults only to supported missing or nil fields.
- **kind:** persisted-format
- **status:** active
