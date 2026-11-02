---
modules: [Jido.Action.Error, Jido.Action.Error.Internal.UnknownError]
---

# Action error obligations

## Purpose

Check the existing public Action error contract during the Covenant trial.
The API source remains the module documentation and `guides/errors.md`.
These obligations refine the existing `ERROR-001` contract ID.

### jido_action.errors.I1 — Constructors preserve supported details
- **scope:** `Jido.Action.Error.validation_error/2`, `Jido.Action.Error.execution_error/2`, `Jido.Action.Error.timeout_error/2`, `Jido.Action.Error.config_error/2`, `Jido.Action.Error.internal_error/2`
- **must:** Return the documented concrete error type and message. Accept plain maps and keyword lists as details. Copy the validation field and value and the timeout into their concrete fields. Discard unsupported detail containers. Retain the documented invalid, execution, configuration, and internal error classes; invalid errors take precedence in an aggregate.
- **kind:** functional
- **status:** active

### jido_action.errors.I3 — Public error maps preserve canonical meaning
- **scope:** `Jido.Action.Error.to_map/1`, `Jido.Action.Error.Internal.UnknownError.message/1`
- **must:** Return the documented type, message, details, and Boolean retry classification. Preserve concrete detail values without transport conversion and omit the top-level stacktrace. Unwrap two-element and three-element error tuples. Map unsupported reasons to an execution error with empty details and no retry. Foreign maps cannot select a canonical error type. An unknown error uses its underlying reason when present. Error maps leave JSON transport conversion to the caller; error structs do not supply automatic JSON encoding.
- **kind:** functional
- **status:** active

### jido_action.errors.I4 — Retry requires a permitted type and a Boolean hint
- **scope:** `Jido.Action.Error.retryable?/1`
- **must:** Return true only for concrete execution or timeout errors with a direct Boolean retry hint set to true. Missing or unsupported hints, other error types, nested hints, and unsupported values cannot request retry. Unwrap two-element and three-element error tuples.
- **kind:** functional
- **status:** active
