---
modules: [Jido.Flow.Inline, Jido.Flow.Inline.Compiler, Jido.Flow.Inline.Owner]
---
# Inline Flow obligations

## Purpose

These obligations define the compile-time host boundary for an embedded Flow.
The public `Jido.Flow.Inline` documentation is the API source. An inline Flow
is an ordinary Flow module after compilation. It is not a fourth Flow data or
execution form.

### jido_action.inline_flow.I1 — Declarations retain normal Flow meaning
- **scope:** `Jido.Flow.Inline.compile!/4`
- **must:** Evaluate the typed path and Flow options once at the owner declaration site. Compile the body with the normal Flow DSL, including configured extensions and inline Steps. Preserve normal Flow metadata, schemas, validation, execution, and source-aware diagnostics. The body has generated-module scope and does not capture owner functions or attributes.
- **kind:** functional
- **status:** active

### jido_action.inline_flow.I2 — Host composition is deterministic
- **scope:** `Jido.Flow.Inline.setup!/1, Jido.Flow.Inline.compile!/4`
- **must:** Repeated setup installs one owner hook pair and preserves declarations and other compile hooks. Declarations emitted by late compile hooks remain indexed. Reject every user clause that can define the reserved owner lookup function, including clauses with default arguments. Reject invalid paths, identities, and Flow options before target module compilation, so these failures do not replace a loaded target. A corrected recompilation can replace that target without retaining old Flow DSL state or terminating processes that already run old code. After preflight passes, a body compilation failure does not restore the previous generated module for new calls.
- **kind:** functional
- **status:** active

### jido_action.inline_flow.I3 — Typed identity and lookup are bounded and inert
- **scope:** `Jido.Flow.Inline.compile!/4, Jido.Flow.Inline.target!/2`
- **must:** Identity uses the owner and complete typed path, independently of Flow metadata. Require a proper path of at least three segments with non-nil atom keys and atom, string, or integer values, starting with `:host` and ending with `role: :flow`; reject invalid, duplicate, or foreign identities. A false compile branch creates no target or index entry. Lookup requires a completed owner, verifies the generated ownership marker, returns only its Flow target, does not run Flow work, and creates no atoms for unknown string paths.
- **kind:** functional
- **status:** active
