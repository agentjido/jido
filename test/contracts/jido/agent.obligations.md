---
modules:
  - Jido.Agent
  - Jido.Agent.Authoring
  - Jido.Agent.Callback
  - Jido.Agent.Codec
  - Jido.Agent.Command
  - Jido.Agent.Composition
  - Jido.Agent.Contract
  - Jido.Agent.Data
  - Jido.Agent.Diff
  - Jido.Agent.Directive
  - Jido.Agent.Directive.Emit
  - Jido.Agent.DSL
  - Jido.Agent.DSL.Discovery
  - Jido.Agent.DSL.Extension
  - Jido.Agent.DSL.Macros
  - Jido.Agent.DSL.Topology
  - Jido.Agent.Error
  - Jido.Agent.Extension
  - Jido.Agent.Mutation
  - Jido.Agent.Plugin
  - Jido.Agent.Plugin.Pipeline
  - Jido.Agent.Plugin.Preparation
  - Jido.Agent.Plugin.Reduction
  - Jido.Agent.Plugin.Spec
  - Jido.Agent.Route
  - Jido.Agent.Runner
  - Jido.Agent.Topology
  - Jido.Agent.Turn
  - Jido.Agent.Turn.SignalHandler
  - Jido.Agent.Validation
---

## Purpose

Protect the current `Jido.Agent.*` value, authoring, direct-command, and
composition boundaries. The component follows code ownership. It does not claim
the AgentServer lifecycle, Directive dispatch, persistence records and stores,
Scheduler provider internals, or shared Registry and Plugin internals.

Public functions use their documented input types. Wrong top-level Elixir types
can raise a function-clause error. Supported inputs return the structured results
defined below.

AgentServer can add durable member slot identities to accepted topology data.
Those values support recovery. They are not credentials and are not part of the
pure authoring guarantees in this component.

## Obligations

### jido.agent.I1 — Equivalent declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Equivalent Map and DSL declarations produce equal canonical Agent definitions.
- **kind:** functional
- **status:** active

### jido.agent.I2 — Neutral definitions

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.definition/1`
- **must:** A definition has nil identity and state. Definition construction rejects values that contain instance identity or state.
- **kind:** functional
- **status:** active

### jido.agent.I3 — Declaration guards

- **scope:** `Jido.Agent.define/1`
- **must:** Definition construction rejects unknown fields and non-positive versions.
- **kind:** functional
- **status:** active

### jido.agent.I4 — Duplicate route policy

- **scope:** `Jido.Agent.define/1`
- **must:** Map authoring rejects duplicate route paths and rejects keyword declarations in place of a plain Map.
- **kind:** functional
- **status:** active

### jido.agent.I5 — Reusable definitions

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Independent instances do not change their source definition or its declaration order.
- **kind:** functional
- **status:** active

### jido.agent.I6 — Current Action contract

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.instantiate/2`
- **must:** Route execution and later instantiation read the current Action schema after code reload.
- **kind:** functional
- **status:** active

### jido.agent.I7 — Instance identity and options

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Instantiation requires a nonempty string identity and accepts only identity and state options.
- **kind:** functional
- **status:** active

### jido.agent.I8 — Initialization defaults

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Initialization applies Zoi defaults and preserves valid false, zero, and empty values.
- **kind:** functional
- **status:** active

### jido.agent.I9 — Complete stored and candidate state

- **scope:** `Jido.Agent.validate/1`, `Jido.Agent.cmd/3`
- **must:** Stored and candidate validation reject missing, extra, or invalid state fields without inserting defaults.
- **kind:** functional
- **status:** active

### jido.agent.I10 — Plugin state ownership

- **scope:** `Jido.Agent.schema/1`, `Jido.Agent.instantiate/2`
- **must:** Domain and Plugin state share one map. Domain and Plugin declarations cannot own the same field, and two Plugin contributions cannot duplicate one owner.
- **kind:** functional
- **status:** active

### jido.agent.I11 — Domain updates

- **scope:** `Jido.Agent.set/2`
- **must:** Set changes domain fields with shallow top-level replacement, validates the complete result, and leaves the source unchanged.
- **kind:** functional
- **status:** active

### jido.agent.I12 — One route selection

- **scope:** `Jido.Agent.Route.select/2`, `Jido.Agent.cmd/3`
- **must:** Select the first declared matching route. Do not run a later wildcard route after the selected executable fails.
- **kind:** ordering
- **status:** active

### jido.agent.I13 — Route input precedence

- **scope:** `Jido.Agent.cmd/3`
- **must:** Shallow-merge route defaults with Signal data taking precedence, and keep the unchanged source Signal in execution context.
- **kind:** functional
- **status:** active

### jido.agent.I14 — Signal input normalization

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Turn.new/2`
- **must:** Accept map, keyword-last-value, and nil input. Reject other input before executable work.
- **kind:** functional
- **status:** active

### jido.agent.I15 — Context and execution options

- **scope:** `Jido.Agent.cmd/3`
- **must:** Reject reserved context keys, preserve other context values, and pass execution options to the executor.
- **kind:** functional
- **status:** active

### jido.agent.I16 — Complete command success

- **scope:** `Jido.Agent.cmd/3`
- **must:** Return a complete valid candidate and the ordered validated Directive batch while retaining Agent identity and unchanged definition fields.
- **kind:** functional
- **status:** active

### jido.agent.I17 — Command failure isolation

- **scope:** `Jido.Agent.cmd/3`
- **must:** A failed command returns no candidate, leaves the source unchanged, and does not prevent a later valid command.
- **kind:** functional
- **status:** active

### jido.agent.I18 — Plugin execution order

- **scope:** `Jido.Agent.cmd/3`
- **must:** Prepare and reduce Plugins in declaration order. Keep package inputs separate and reject executable writes to Plugin-owned state.
- **kind:** ordering
- **status:** active

### jido.agent.I19 — Direct effect boundary

- **scope:** `Jido.Agent.cmd/3`
- **must:** Return Directives without dispatch. A later validation error cannot undo work that the executable already performed.
- **kind:** functional
- **status:** active

### jido.agent.I20 — Agent document envelope

- **scope:** `Jido.Agent.Codec`, `Jido.Agent.to_json/2`, `Jido.Agent.from_json/2`
- **must:** Round-trip valid definitions and instances through a trusted Registry, and reject a malformed Agent document.
- **kind:** persisted-format
- **status:** active

### jido.agent.I21 — Generated Signal helpers

- **scope:** `Jido.Agent.__using__/1`
- **must:** Helpers require plain-map data, protect type and data from envelope overrides, preserve empty data, and create a fresh Signal identity.
- **kind:** functional
- **status:** active

### jido.agent.I23 — Structured supported-input errors

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.cmd/3`
- **must:** Invalid supported inputs return structured errors with nonempty messages. Routing errors retain their code, and Plugin callback failures retain application rejection reasons or exception values.
- **kind:** functional
- **status:** active

### jido.agent.I24 — Raising constructor parity

- **scope:** `Jido.Agent.define!/1`, `Jido.Agent.instantiate!/2`
- **must:** Bang constructors raise the same validation error that their tuple form returns.
- **kind:** functional
- **status:** active

### jido.agent.I25 — Public Agent entry points

- **scope:** `Jido.Agent`
- **must:** Keep define, instantiate, validate, schema, mutate, and cmd. Do not restore removed new, validate_instance, complete_schema, handle_signal, checkpoint, or restore wrappers.
- **kind:** functional
- **status:** active

### jido.agent.I26 — One topology value

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.Topology`
- **must:** A leaf has empty agent and connection lists. Mutation can add a named member and an explicit broadcast connection. Root is reserved, and removed legacy topology collections remain invalid.
- **kind:** functional
- **status:** active

### jido.agent.I36 — Atomic candidate composition

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.mutate/2`
- **must:** Apply state and ordered definition changes to one candidate. Reject an invalid state or Directive batch without changing the source.
- **kind:** functional
- **status:** active

### jido.agent.I41 — Ordered definition edits

- **scope:** `Jido.Agent.mutate/2`, `Jido.Agent.Directive`
- **must:** Apply strict add, update, replace, remove, and reorder operations in batch order. Preserve unrelated values and report the net Diff.
- **kind:** functional
- **status:** active

### jido.agent.I42 — Final topology validation

- **scope:** `Jido.Agent.Topology`, `Jido.Agent.mutate/2`
- **must:** Resolve endpoint references after the complete batch, reject a removed endpoint that remains connected, and require broadcast delivery for a counted destination.
- **kind:** functional
- **status:** active

### jido.agent.I43 — Plugin declaration edits

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Directive`
- **must:** Initialize new Plugin state, preserve compatible state, require explicit disposal or migration, and reject an affected Plugin Directive in the same change batch.
- **kind:** functional
- **status:** active

### jido.agent.I45 — Current-state topology binding

- **scope:** `Jido.Agent.Topology.bind/2`
- **must:** Resolve copied child state and counts from the supplied parent state without changing the stored symbolic definition or retaining a prior bound value.
- **kind:** functional
- **status:** active
