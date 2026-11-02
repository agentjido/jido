---
modules:
  - Jido.Flow.Codec
  - Jido.Flow.Codec.Limits
  - Jido.Flow.Codec.Paths
  - Jido.Flow.Codec.Reader
  - Jido.Flow.Codec.Value
  - Jido.Flow.Codec.Writer
---
# Codec public promise obligations

## Purpose

Check focused facets of the [reviewed public promises](../../../guides/public-api-contract-review.md). The module reference defines the supported API. Passing tags are evidence for these facets, not complete branch or acceptance-matrix coverage.

### jido_action.codec.I5 — Version two preserves portable Flow meaning
- **scope:** `Jido.Authoring.encode/2, Jido.Authoring.decode/2, Jido.Flow.Codec`
- **must:** Encode current supported components and values as deterministic JSON-compatible `vsn` 2 maps. Decode them to equivalent canonical Flow meaning. Reject other document `vsn` values and unregistered write values. Reject version 1 with an explicit Dispatch migration requirement. JSON byte order is not a stable storage promise.
- **kind:** persisted-format
- **status:** active

### jido_action.codec.I6 — Stored identifiers use the trusted Registry
- **scope:** `Jido.Authoring.encode/2, Jido.Authoring.decode/2, Jido.Flow.Codec`
- **must:** Resolve stored Flow target, schema, and atom identifiers only through exact versioned trusted Registry entries of the required kind. Reject versionless, unknown, or wrong-kind identifiers without running Action work.
- **kind:** security
- **status:** active

### jido_action.codec.I7 — Invalid stored data has bounded ordered diagnostics
- **scope:** `Jido.Authoring.decode/2, Jido.Flow.Codec`
- **must:** Reject malformed fields, unknown keys, invalid UTF-8, unsupported tags, and documents over the stated depth, width, or total-node limits. Safety checks precede envelope checks. Decode returns the first error; diagnosis returns errors from the current phase with useful JSON paths and the same semantic field order as data definitions. Never return a partial Flow.
- **kind:** security
- **status:** active
