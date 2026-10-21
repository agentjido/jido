---
modules:
  - Jido.SignalAction
---

## Purpose

Protect the Jido-owned value that combines one Action declaration with one
input Signal contract and an optional output Signal contract. This component
owns declaration validation, shared input conversion, Signal construction,
reply validation, and reply correlation.

It does not own Action execution, Signal routing or dispatch, Agent route
authoring, or AgentServer commit timing.

## Obligations

### jido.signal_action.I1 — One combined declaration

- **scope:** `use Jido.SignalAction`, generated metadata functions
- **must:** Define one native Action and one input Signal definition in the same module. Require a name, non-blank description, positive version, and input contract. Reject duplicate or unknown declaration options. Expose the same input schema through Action parameter and Signal data validation.
- **kind:** functional
- **status:** active

### jido.signal_action.I2 — Static Signal definition forms

- **scope:** `use Jido.SignalAction`, input and output declarations
- **must:** Accept an inline Signal keyword declaration or a compiled Signal definition module. Require a full string type and static map-shaped schema. Reject tuple forms, unavailable or incomplete modules, and invalid Signal declarations at compile time.
- **kind:** functional
- **status:** active

### jido.signal_action.I3 — Explicit output modes

- **scope:** `use Jido.SignalAction`, generated Action output contract
- **must:** Let output be absent, an ordinary Action output schema, or one Signal definition. A Signal output supplies the Action output schema and enables replies. An absent or ordinary Action output does not invent an output Signal or failure Signal.
- **kind:** functional
- **status:** active

### jido.signal_action.I4 — Validated input construction

- **scope:** generated `new/2`, `validate_data/1`
- **must:** Validate, default, and coerce input data through the shared schema before building a Signal. Own the Signal type, data, and data-schema fields, apply declared source and content-type defaults, accept other valid envelope options, and perform no execution or dispatch.
- **kind:** functional
- **status:** active

### jido.signal_action.I5 — Raising constructor parity

- **scope:** generated `new!/2`
- **must:** Return the same Signal as `new/2` on success. Raise the input parse error for invalid data and an argument error for invalid Signal envelope options.
- **kind:** functional
- **status:** active

### jido.signal_action.I6 — Validated reply construction

- **scope:** generated `reply/3`, `Jido.SignalAction.reply/4`
- **must:** Require a valid request Signal that matches the input type and data-schema contract, one declared output Signal, and output data accepted by its required map-shaped schema. Build the declared output Signal with valid caller options and perform no dispatch.
- **kind:** functional
- **status:** active

### jido.signal_action.I7 — Fresh correlated replies

- **scope:** generated `reply/3`, reply trace context
- **must:** Give every reply a fresh identity, preserve the request trace and trace state, set the request ID as causation, and leave the request unchanged. Caller options cannot replace reply identity or correlation.
- **kind:** functional
- **status:** active
