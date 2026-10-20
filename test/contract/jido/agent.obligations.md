---
modules:
  - Jido.Agent
  - Jido.Agent.Authoring
  - Jido.Agent.Codec
  - Jido.Agent.Composition
  - Jido.Agent.Data
  - Jido.Agent.Diff
  - Jido.Agent.Directive
  - Jido.Agent.Directive.Emit
  - Jido.Agent.Error
  - Jido.Agent.Extension
  - Jido.Agent.Mutation
  - Jido.Agent.Topology
  - Jido.Agent.Validation
---

## Purpose

Protect the current `Jido.Agent.*` value, authoring, validation, and composition
boundaries. The component follows code ownership. It does not claim pure Agent
evaluation, the AgentServer lifecycle, Directive dispatch, persistence records
and stores, Scheduler provider internals, or shared Registry and Plugin
internals.

Public functions use their documented input types. Wrong top-level Elixir types
can raise a function-clause error. Supported inputs return the structured results
defined below.

AgentServer can add durable member slot identities to accepted topology data.
Those values support recovery. They are not credentials and are not part of the
pure authoring guarantees in this component.

This component owns the logical topology value in an Agent definition. It does
not restore or claim the retired standalone `jido.topology` component.

## Obligations

**Definitions and instances**

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
- **must:** Retired. `jido.agent_evaluation.I4` owns current executable contract evaluation.
- **kind:** functional
- **status:** retired

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

### jido.agent.I9 — Complete stored state

- **scope:** `Jido.Agent.validate/1`
- **must:** Stored state validation rejects missing, extra, or invalid fields without inserting defaults.
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

**Retired direct commands**

### jido.agent.I12 — One route selection

- **scope:** `Jido.Agent.Route.select/2`, `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I1` owns fixed route selection.
- **kind:** ordering
- **status:** retired

### jido.agent.I13 — Route input precedence

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I1` and `jido.agent_evaluation.I2` own source binding and route input.
- **kind:** functional
- **status:** retired

### jido.agent.I14 — Signal input normalization

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Turn.new/2`
- **must:** Retired. `jido.agent_evaluation.I2` owns Signal input normalization.
- **kind:** functional
- **status:** retired

### jido.agent.I15 — Context and execution options

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I3` owns execution context and options.
- **kind:** functional
- **status:** retired

### jido.agent.I16 — Complete command success

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I5`, `jido.agent_evaluation.I7`, and `jido.agent_evaluation.I9` own candidate and Directive results.
- **kind:** functional
- **status:** retired

### jido.agent.I17 — Command failure isolation

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I5` owns evaluation failure isolation.
- **kind:** functional
- **status:** retired

### jido.agent.I18 — Plugin execution order

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I6` and `jido.agent_evaluation.I8` own pure Agent Plugin execution.
- **kind:** ordering
- **status:** retired

### jido.agent.I19 — Direct effect boundary

- **scope:** `Jido.Agent.cmd/3`
- **must:** Retired. `jido.agent_evaluation.I9` owns the pure result and effect boundary.
- **kind:** functional
- **status:** retired

**Documents and public surface**

### jido.agent.I20 — Agent document envelope

- **scope:** `Jido.Agent.Codec`, `Jido.Agent.to_json/2`, `Jido.Agent.from_json/2`
- **must:** Write a portable definition through a trusted Registry, omit instance ID and state, read through `Jido.Agent.define/1`, and reject a malformed or unsupported Agent document.
- **kind:** persisted-format
- **status:** active

### jido.agent.I21 — Generated Signal helpers

- **scope:** `Jido.Agent.__using__/1`, `Jido.Agent.input_signal/4`, `Jido.Agent.input_signal!/4`
- **must:** Tuple and bang helpers require plain-map data, protect type and data from envelope overrides, preserve empty data, and create a fresh Signal identity. Bang helpers raise only for Signal construction errors and do not validate the route target input.
- **kind:** functional
- **status:** active

### jido.agent.I22 — Structured supported-input errors

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`
- **must:** Invalid supported authoring inputs return structured errors with nonempty messages.
- **kind:** functional
- **status:** active

### jido.agent.I23 — Raising constructor parity

- **scope:** `Jido.Agent.define!/1`, `Jido.Agent.instantiate!/2`
- **must:** Bang constructors raise the same validation error that their tuple form returns.
- **kind:** functional
- **status:** active

### jido.agent.I24 — Public Agent entry points

- **scope:** `Jido.Agent`
- **must:** Keep define, instantiate, validate, schema, mutate, and cmd. Do not restore removed new, validate_instance, complete_schema, handle_signal, checkpoint, or restore wrappers.
- **kind:** functional
- **status:** active

**Definition composition**

### jido.agent.I25 — One topology value

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.Topology`
- **must:** A leaf has empty agent and connection lists. Mutation can add a named member and an explicit broadcast connection. Root is reserved, and removed legacy topology collections remain invalid.
- **kind:** functional
- **status:** active

### jido.agent.I26 — Atomic definition edits

- **scope:** `Jido.Agent.mutate/2`
- **must:** Apply ordered definition changes to one candidate. Reject an invalid edit batch without changing the source.
- **kind:** functional
- **status:** active

### jido.agent.I27 — Ordered definition edits

- **scope:** `Jido.Agent.mutate/2`, `Jido.Agent.Directive`
- **must:** Apply strict add, update, replace, remove, and reorder operations in batch order. Preserve unrelated values and report the net Diff.
- **kind:** functional
- **status:** active

### jido.agent.I28 — Final topology validation

- **scope:** `Jido.Agent.Topology`, `Jido.Agent.mutate/2`
- **must:** Resolve endpoint references after the complete batch, reject a removed endpoint that remains connected, and require broadcast delivery for a counted destination.
- **kind:** functional
- **status:** active

### jido.agent.I29 — Plugin declaration edits

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Directive`
- **must:** Initialize new Plugin state, preserve compatible state, require explicit disposal or migration, and reject an affected Plugin Directive in the same change batch.
- **kind:** functional
- **status:** active

### jido.agent.I30 — Current-state topology binding

- **scope:** `Jido.Agent.Topology.bind/2`
- **must:** Resolve copied child state and counts from the supplied parent state without changing the stored symbolic definition or retaining a prior bound value.
- **kind:** functional
- **status:** active
