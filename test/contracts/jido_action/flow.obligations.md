---
modules:
  - Jido.Flow
  - Jido.Flow.Component
  - Jido.Flow.DSL
  - Jido.Flow.DSL.Choice
  - Jido.Flow.DSL.ChoiceMacros
  - Jido.Flow.DSL.ChoiceOption
  - Jido.Flow.DSL.Handoff
  - Jido.Flow.DSL.Invoke
  - Jido.Flow.DSL.Entity
  - Jido.Flow.DSL.Extension
  - Jido.Flow.DSL.InlineStep
  - Jido.Flow.DSL.Iterate
  - Jido.Flow.DSL.IterateMacros
  - Jido.Flow.DSL.IterateState
  - Jido.Flow.DSL.Lowerer
  - Jido.Flow.DSL.MacroSupport
  - Jido.Flow.DSL.Macros
  - Jido.Flow.DSL.MapNode
  - Jido.Flow.DSL.ModuleCompiler
  - Jido.Flow.DSL.Otherwise
  - Jido.Flow.DSL.Output
  - Jido.Flow.DSL.Reduce
  - Jido.Flow.DSL.Schema
  - Jido.Flow.DSL.SourceMap
  - Jido.Flow.DSL.Step
  - Jido.Flow.DSL.ValueParser
  - Jido.Flow.Definition
  - Jido.Flow.Error
  - Jido.Flow.Extension
  - Jido.Flow.FieldError
  - Jido.Flow.Graph
  - Jido.Flow.GraphValidation
  - Jido.Flow.Identity
  - Jido.Flow.Ref
  - Jido.Flow.Value
---
# Flow public promise obligations

## Purpose

Check focused facets of the [reviewed public promises](../../../guides/public-api-contract-review.md). The module reference defines the supported API. Passing tags are evidence for these facets, not complete branch or acceptance-matrix coverage.

### jido_action.flow.I7 — Authoring forms preserve one Flow meaning
- **scope:** `Jido.Flow.new/1, Jido.Flow.__using__/1, Jido.Flow.Codec`
- **must:** DSL, public data definitions, and stored documents produce equivalent validated Flow meaning for supported components, references, schemas, and outputs. Generated names and source locations need not be equal.
- **kind:** functional
- **status:** active

### jido_action.flow.I8 — Dependencies and explicit output define valid graphs
- **scope:** `Jido.Flow.new/1, Jido.Flow.validate/1, Jido.Flow.dependencies/1`
- **must:** References and needs create dependencies; source order does not. Require explicit non-nil output, unique component names, valid reference scopes, and acyclic dependencies. Invoke is composable, can have downstream nodes, and can occur more than once. Handoff is the sole graph terminal and its complete result is the Flow output. Invalid graphs retain structured errors and defined diagnostic order.
- **kind:** ordering
- **status:** active

### jido_action.flow.I9 — Validation and inspection do not run Action work
- **scope:** `Jido.Flow.validate/1, Jido.Flow.dependencies/1, Jido.Flow.explain/1, Jido.Exec.compile/2`
- **must:** Structural validation, inspection, encoding, and compilation do not call Action run/2. Structural checks do not validate target callbacks; Exec compilation checks trusted targets. Trusted module, schema, and Flow builders can run during compilation.
- **kind:** functional
- **status:** active

### jido_action.flow.I10 — Semantic identity describes canonical graph data
- **scope:** `Jido.Flow.semantic_identity/1, Jido.Flow.explain/1, Jido.Flow.Codec`
- **must:** Equivalent canonical graphs have deterministic versioned identity independent of source order, descriptions, and component metadata. References and expressions remain distinct from literal maps. Codec round trips preserve identity. Identity does not identify deployed Action code.
- **kind:** functional
- **status:** active

### jido_action.flow.I11 — Extensions lower to supported declarations
- **scope:** `Jido.Flow.Extension, Jido.Flow.__using__/1`
- **must:** Configured compile-time extensions expand to ordinary Flow declarations and retain graph, inline Action, and source-location rules. Reject invalid or duplicate extension configuration. Data definitions and stored documents do not load extensions.
- **kind:** functional
- **status:** active
