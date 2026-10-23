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
  - Jido.Agent.View
---

## Purpose

Protect the Agent-specific value and authoring boundary. This component owns
canonical Agent definitions and instances, state schemas, the Agent DSL,
logical topology, extension contributions, definition mutation and Diff data,
the Agent document codec adapter, and safe Agent views.

The component follows behavior ownership. It does not claim shared Authoring,
Registry, Document, Value, or Discovery behavior from `jido_action`. It also
does not claim pure Agent evaluation, AgentServer commands and lifecycle,
Agent references and process addressing, Directive dispatch, persistence, or
bundled Plugin runtime behavior.

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

### jido.agent.I1 — Canonical DSL parity

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** The optional, single-use `state`, `plugins`, `routes`, and `topology` sections lower state schema, declared initial state, provider configuration, ordered routes, logical members, and connections into the same canonical Agent definition as an equivalent Map declaration. `use Jido.Agent` owns static metadata. Selected providers can add non-core sections without replacing a core section. The removed `agent do` block is invalid.
- **kind:** functional
- **status:** active

### jido.agent.I2 — Neutral definitions

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.definition/1`
- **must:** A definition has nil identity and state. Definition construction rejects values that contain instance identity or state.
- **kind:** functional
- **status:** active

### jido.agent.I3 — Declaration guards

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Definition construction rejects unknown fields or use options, invalid stable authoring IDs, non-positive versions, invalid schemas, and repeated core sections or fields.
- **kind:** functional
- **status:** active

### jido.agent.I4 — Route declaration policy

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Authoring rejects duplicate route paths or helper names. A generated helper requires an exact route and a lowercase atom that starts with a letter and contains only letters, digits, and underscores. Map authoring rejects keyword declarations in place of a plain Map.
- **kind:** functional
- **status:** active

### jido.agent.I5 — Reusable definitions

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Independent instances do not change their source definition or its declaration order.
- **kind:** functional
- **status:** active

### jido.agent.I6 — Declared initial state

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`
- **must:** A Map definition or `state do` section can declare one plain, static `initial_state` Map. The DSL and Map forms lower to the same field. The source definition stays unchanged.
- **kind:** functional
- **status:** active

### jido.agent.I7 — Instance identity and options

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Instantiation requires a nonempty string identity and accepts only identity and state options. State must be a plain Map.
- **kind:** functional
- **status:** active

### jido.agent.I8 — Initialization defaults

- **scope:** `Jido.Agent.instantiate/2`
- **must:** For a new instance, initialization merges explicit state over declared initial state and passes that candidate to the Agent module's optional `initialize/2` callback with Jido-owned identity and topology context. The callback returns the complete candidate as `{:ok, state}` or stops creation with `{:error, reason}`. Zoi then adds defaults and validates the result. Invalid results and callback failures stop creation. Validation and restore do not run the callback. Initialization preserves valid false, zero, and empty values.
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

**Documents and public surface**

### jido.agent.I20 — Agent document adapter

- **scope:** `Jido.Authoring.encode/2`, `Jido.Authoring.decode/2`, `Jido.Authoring.encode_json/2`, `Jido.Authoring.decode_json/2`, `Jido.Agent.Codec`
- **must:** Register the Agent document type with shared Authoring. Write a portable Agent definition, including declared initial state, through a trusted Registry. Omit instance ID, instance state, and the module-owned `initialize/2` callback. Read through `Jido.Agent.define/1`, and reject a malformed or unsupported Agent document. Read a version 1 document that omits initial state as an empty initial-state Map. Shared document, Registry, JSON, and portable-value rules remain owned by `jido_action`.
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
- **must:** Keep `use Jido.Agent`, `schema/1`, `define/1`, `define!/1`, `validate/1`, `definition?/1`, `instance?/1`, `definition/1`, `instantiate/1,2`, `instantiate!/1,2`, `mutate/2`, `set/2`, and `cmd/2,3` as the documented and typed Agent facade. Keep runtime projection, direct Signal-helper support, raw schema data, and transition functions hidden. Do not restore removed `new`, `validate_instance`, `complete_schema`, `handle_signal`, `checkpoint`, or `restore` wrappers.
- **kind:** functional
- **status:** active

### jido.agent.I31 — Safe Agent views

- **scope:** `Jido.Agent.View.project/3`
- **must:** Project a module, definition, or instance as one bounded JSON-safe summary. Expose code and schema values only through trusted Registry references. Do not expose Agent state, metadata, Plugin options, route defaults, or raw modules. Do not start or contact an Agent process.
- **kind:** security
- **status:** active

### jido.agent.I32 — Generated Agent module facade

- **scope:** `Jido.Agent.__using__/1`, generated Agent modules
- **must:** Generate documented `vsn/0`, `schema/0`, `definition/0`, `instantiate/0,1`, `instantiate!/0,1`, `cmd/2,3`, and `route_executable!/1` functions that delegate to the canonical Agent boundaries. Keep compiler authoring metadata hidden. `route_executable!/1` returns the Action or Flow target for an exact executable route. It raises `ArgumentError` for a terminal handler or unknown path.
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

- **scope:** `Jido.Agent.mutate/2`, `Jido.Agent.Directive`
- **must:** Initialize new Plugin state, preserve compatible state, and require explicit disposal or migration when a Plugin declaration changes.
- **kind:** functional
- **status:** active

### jido.agent.I30 — Current-state topology binding

- **scope:** `Jido.Agent.Topology.bind/2`
- **must:** Resolve copied child state and counts from the supplied parent state without changing the stored symbolic definition or retaining a prior bound value.
- **kind:** functional
- **status:** active
