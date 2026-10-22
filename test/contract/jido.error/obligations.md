---
modules:
  - Jido.Error
---

## Purpose

Protect the shared Jido error taxonomy, constructors, stable common codes,
retry classification, and bounded public projection.

This component does not own `Jido.Agent.Error`, `Jido.Plugin.Error`, failure
conversion in a domain component, adjacent-package error types, or runtime
retry and recovery policy.

## Obligations

### jido.error.I1 — Fixed taxonomy and constructors

- **scope:** Splode classes, public error modules, constructors
- **must:** Provide the five invalid, execution, routing, timeout, and internal classes. Keep the six documented public error modules with their fixed class and fields. Accept keyword or map options, normalize details to a map, apply documented defaults, and keep CompensationError as an execution-class compatibility type.
- **kind:** functional
- **status:** active

### jido.error.I2 — Closed common-code registry

- **scope:** `stable_codes/0`, `code/1`
- **must:** Publish the exact registered Jido-owned codes without duplicates. Read only a registered code from an error, a two- or three-element error result, or a version-1 projection. Return nil for messages, raw atoms, adjacent-package codes, and unknown values.
- **kind:** functional
- **status:** active

### jido.error.I3 — Exact version-1 projection

- **scope:** `to_map/1`, error-type normalization
- **must:** Return exactly type, message, details, and retryable? keys. Canonicalize Jido, Agent, Action, Signal, atom, and string error types to the supported public vocabulary. Keep stable codes inside details and do not add a new projection version or copy an adjacent error into a Jido error type.
- **kind:** functional
- **status:** active

### jido.error.I4 — Bounded safe transport

- **scope:** public messages and details
- **must:** Bound container depth, nested message and compensation-cause traversal, collection size, text, and keys. Redact sensitive-key values, omit stacktrace-key values, contain improper lists and opaque terms, repair invalid UTF-8, and produce JSON-encodable values without exposing rejected private data.
- **kind:** security
- **status:** active

### jido.error.I5 — Stable retry classification

- **scope:** `retryable?/1`, projection retry flag
- **must:** Treat validation, invalid-action, and configuration failures as non-retryable by default and all other or unknown failures as retryable. Let an explicit Boolean retry, retryable, or retryable? detail override the default through supported maps, keyword details, and error tuple wrappers. Bound nested hint lookup to the public traversal depth.
- **kind:** functional
- **status:** active

### jido.error.I6 — Defensive rendering containment

- **scope:** arbitrary terms, exceptions, Splode unknown errors
- **must:** Project any term without raising, throwing, or exiting because message or inspection code fails. Use an internal type and bounded valid text for unknown values. Keep the same containment when Splode wraps an unknown value.
- **kind:** functional
- **status:** active
