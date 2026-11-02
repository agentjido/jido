---
modules:
  - Jido.Authoring.Document
  - Jido.Authoring.Registry
  - Jido.Authoring.Value
---
# Portable authoring obligations

## Purpose

Define the shared storage guarantees that document owners can use without
depending on the Flow document format. Each owner still owns its envelope,
version, fields, reference kinds, and semantic validation.

### jido_action.authoring.I1 — Typed identifiers are stable and inert
- **scope:** `Jido.Authoring.Registry.new/1, Jido.Authoring.Registry.new!/1, Jido.Authoring.Registry.resolve/3, Jido.Authoring.Registry.reference/3`
- **must:** Validate bounded stable identifiers, explicit positive versions, supported atom kinds, and one reference for each exact typed value. Reserve `:alias` and support other package-defined kinds without loading modules, running work, deriving module names, or creating atoms from stored identifiers. Reject versionless references, invalid entries, unknown identifiers, wrong kinds, and duplicate writes.
- **kind:** security
- **status:** active

### jido_action.authoring.I2 — Portable values have a closed round-trip grammar
- **scope:** `Jido.Authoring.Value.encode/2, Jido.Authoring.Value.decode/2`
- **must:** Round trip valid JSON scalars, proper lists, plain maps with supported keys, and atoms registered as kind `:atom`. Every successful decode must be encodable with the same Registry. Reject invalid UTF-8, improper lists, structs, unsupported values or keys, duplicate decoded keys, invalid tags, and non-atom atom bindings. Complete-document limits are checked before portable value decoding.
- **kind:** persisted-format
- **status:** active

### jido_action.authoring.I3 — Complete document limits stay owner-neutral
- **scope:** `Jido.Authoring.Document.check/1, Jido.Authoring.Registry, Jido.Authoring.Value`
- **must:** Bound complete documents by nesting depth, collection size, total nodes, and proper-list shape before owner-specific decoding. Report the active maximum in structured limit error details. Do not treat this resource check as envelope, value, target, or semantic validation. Permit a downstream owner to compose the three public APIs and to share one Registry with other document owners.
- **kind:** security
- **status:** active
