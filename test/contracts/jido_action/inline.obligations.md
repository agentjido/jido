---
modules: [Jido.Action.Inline, Jido.Action.Inline.Parser, Jido.Action.Inline.Compiler, Jido.Action.Inline.Owner, Jido.Authoring.Options]
---
# Inline Action obligations

## Purpose

These obligations refine `ACT-005` and the trusted host target boundary.
The public Inline module documentation is the API source.

### jido_action.inline.I1 — Header parsing keeps the selected host grammar
- **scope:** `Jido.Action.Inline.parse_bound!/3, Jido.Action.Inline.parse_callback!/3`
- **must:** Bound headers return source AST without evaluating it. Callback headers receive params directly. Preserve supported patterns, clauses and guards. Reject improper bindings, ambiguous or unsupported options, invalid context bindings and malformed clause bodies with a source-aware CompileError.
- **kind:** functional
- **status:** active

### jido_action.inline.I2 — Generated Actions keep owner scope and normal Action behavior
- **scope:** `Jido.Action.Inline.compile!/4`
- **must:** Emit an ordinary Action with the owner lexical aliases, imports, attributes, private helpers and body source lines. Evaluate metadata, schemas, name and typed path once at the declaration site. Bind callback context separately from params. Remove only the requested declaration imports. Input and output validation use the normal Action boundary. A rejected static configuration must not replace an existing target. Repeated setup and host hooks preserve declarations. Reserved owner function conflicts fail with source-aware errors. Flow inline Steps and extracted targets use the same Action validation and result rules; rejected declarations preserve the loaded target and allow a corrected retry.
- **kind:** functional
- **status:** active

### jido_action.inline.I3 — Typed identity and lookup are inert
- **scope:** `Jido.Action.Inline.target!/2, Jido.Action.Inline.compile!/4`
- **must:** Identity uses the owner and complete typed path independently of Action metadata. Reject invalid, duplicate or foreign paths before replacement. A false compile branch creates no target or index entry. Lookup after compilation returns only the Action target and performs no work or atom allocation for unknown paths. Compilation requires an open owner and lookup requires a completed owner.
- **kind:** functional
- **status:** active
