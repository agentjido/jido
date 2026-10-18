---
modules:
  - Jido.Agent
  - Jido.Agent.DSL
  - Jido.Agent.Route
  - Jido.Agent.Contract
  - Jido.Agent.Data
  - Jido.Agent.DSL.Macros
  - Jido.Agent.Authoring
  - Jido.Agent.Extension
  - Jido.Agent.Validation
  - Jido.Agent.Mutation
  - Jido.Agent.Diff
  - Jido.Agent.Codec
  - Jido.Plugin.Codec
  - Jido.Agent.Runner
  - Jido.Agent.Turn
  - Jido.Agent.Plugin
  - Jido.Agent.Plugin.Pipeline
  - Jido.Agent.Callback
  - Jido.Agent.Topology
  - Jido.Persistence.Snapshot
  - Jido.Persistence.AgentCheckpoint
  - Jido.Agent.Command
  - Jido.Agent.Directive
  - Jido.AgentServer.Directive
  - Jido.Agent.Composition
  - Jido.Persistence
  - Jido.Persistence.Record
---

## Purpose

Protect Agent authoring, canonical definitions, instances, and direct commands.
Use [the Agent evolution specification](../../../AGENT_EVOLUTION_SPEC.md) for
the mutation, Diff, snapshot, upgrade, Map, DSL, and trusted JSON contracts.
There is no compatibility requirement for removed V2 or earlier V3 APIs.

Topology records immediate agents and output connections. Provider contributions
hold Plugin configuration once. Definitions and instances use one Agent struct.
Authoring and mutation do not start processes. AgentServer activation is a
separate boundary. Tests cover current authoring, ordered mutations, complete
state, snapshot provenance, and explicit upgrade Actions.

## Obligations

### jido.agent.I1 — Equivalent declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Equivalent independently authored Maps and DSL declarations produce exactly equal canonical Agent structs when provenance is equal.
- **why:** One canonical value must serve each authoring form.
- **kind:** functional
- **status:** active

### jido.agent.I2 — Neutral definitions

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.define/1`, `Jido.Agent.definition/1`
- **must:** A definition has nil identity and nil state. The definition constructor rejects identity-only, state-only, and instance values.
- **why:** Definition data must be reusable.
- **kind:** functional
- **status:** active

### jido.agent.I3 — Validated declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.define/1`
- **must:** Validate fields, versions, schemas, executable targets, and Plugin declarations. Reject unknown fields.
- **why:** Invalid declarations must fail before execution.
- **kind:** functional
- **status:** active

### jido.agent.I4 — Duplicate policies

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Reject duplicate route paths, helper names, member names, provider IDs, and repeated core DSL fields. Preserve declaration order. Map authoring accepts plain Maps, not keyword declarations.
- **why:** Each language has an explicit duplicate policy.
- **kind:** functional
- **status:** active

### jido.agent.I5 — Stable reusable values

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`
- **must:** Reuse does not change the definition. Preserve declaration order and exact values.
- **why:** A definition must support independent instances.
- **kind:** functional
- **status:** active

### jido.agent.I6 — Current dependency contracts

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Generated module definition access and instantiation read current Action and Plugin contracts after reload. Do not retain stale derived schemas.
- **why:** Code reload must not use old validation contracts.
- **kind:** functional
- **status:** active

### jido.agent.I7 — Instance identity and options

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Accept only explicit nonempty string identity and state overrides. Reject missing, nil, and empty identity. All other definition fields stay equal.
- **why:** Identity belongs to the instance.
- **kind:** functional
- **status:** active

### jido.agent.I8 — Initialization defaults

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Initialize with native static Zoi defaults. Preserve valid supplied values, including false, zero, and empty collections. A supplied nil can select a Zoi default. Stored validation never inserts defaults or changes values.
- **why:** Defaults must follow a stated initialization policy.
- **kind:** functional
- **status:** active

### jido.agent.I9 — Stored and candidate validation

- **scope:** `Jido.Agent.validate_instance/1`, `Jido.Agent.cmd/3`
- **must:** Stored validation does not apply defaults or conversions. Candidates must retain every required defaulted field.
- **why:** A partial result must not become complete through defaults.
- **kind:** functional
- **status:** active

### jido.agent.I10 — Combined state ownership

- **scope:** `Jido.Agent.complete_schema/1`, `Jido.Agent.instantiate/2`
- **must:** Complete state is one map with domain and Plugin-owned fields. Reject domain/Plugin and Plugin/Plugin ownership conflicts.
- **why:** Each Plugin owns its state field.
- **kind:** functional
- **status:** active

### jido.agent.I11 — Domain updates

- **scope:** `Jido.Agent.set/2`
- **must:** Set only domain fields with shallow top-level replacement, validate the complete result, and preserve the source value.
- **why:** State updates must keep ownership and invariants.
- **kind:** functional
- **status:** active

### jido.agent.I12 — One executable selection

- **scope:** `Jido.Agent.Route.select/2`
- **must:** Select the first declared matching route only. Wildcards must be explicit and do not cause multiple handlers to run. No fallback executes after a selected handler fails.
- **why:** A command has one source and one executable.
- **kind:** ordering
- **status:** active

### jido.agent.I13 — Route input precedence

- **scope:** `Jido.Agent.handle_signal/2`, `Jido.Agent.cmd/3`
- **must:** Shallow-merge route defaults with supplied input taking precedence. Keep the original Signal in execution context.
- **why:** Input normalization must not alter the source envelope.
- **kind:** functional
- **status:** active

### jido.agent.I14 — Signal input normalization

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.Turn.new/2`
- **must:** Accept map, keyword-last-value, and nil input. Reject invalid input before executable work.
- **why:** Input boundaries must be consistent.
- **kind:** functional
- **status:** active

### jido.agent.I15 — Context and execution options

- **scope:** `Jido.Agent.cmd/3`
- **must:** Reject reserved caller context keys. Preserve allowed caller context and forward execution options to the executor.
- **why:** Direct execution must honor its caller options.
- **kind:** functional
- **status:** active

### jido.agent.I16 — Complete command success

- **scope:** `Jido.Agent.cmd/3`
- **must:** Return a complete valid candidate and ordered valid Directives. Keep code definition fields and identity; only explicit composition and Plugin changes can change their current declarations.
- **why:** Successful values must be safe for the caller to accept.
- **kind:** functional
- **status:** active

### jido.agent.I17 — Failure and next command

- **scope:** `Jido.Agent.cmd/3`
- **must:** A failed command returns no candidate and preserves the source. A later valid command can succeed from that source.
- **why:** Failure must not leak candidate state.
- **kind:** functional
- **status:** active

### jido.agent.I18 — Plugin order and boundaries

- **scope:** `Jido.Agent.cmd/3`
- **must:** Prepare and reduce Plugins in declaration order. Package inputs remain separate. Executables cannot change Plugin-owned state; reducers return only their own field.
- **why:** Plugins must compose without state or input conflicts.
- **kind:** ordering
- **status:** active

### jido.agent.I19 — Direct effects boundary

- **scope:** `Jido.Agent.cmd/3`
- **must:** Return Directives without dispatch. An error does not undo external work already performed by callbacks or executables.
- **why:** The direct caller owns effects and recovery.
- **kind:** functional
- **status:** active

### jido.agent.I20 — Definition document format

- **scope:** `Jido.Agent.Codec`
- **must:** Encode and decode the complete canonical Agent through an explicit trusted Registry. Reject unknown modules, atoms, fields, or unsupported values. Never create atoms from untrusted document strings.
- **why:** Authoring documents must not become executable code or checkpoints.
- **kind:** persisted-format
- **status:** active

### jido.agent.I21 — Generated Signal helpers

- **scope:** `Jido.Agent.__using__/1`
- **must:** Preserve absent input fields, require plain-map input, protect type/data from envelope overrides, validate the envelope, and defer executable validation.
- **why:** Helpers construct Signals without changing execution policy.
- **kind:** functional
- **status:** active

### jido.agent.I22 — Authoring evaluation and lowering

- **scope:** `Jido.Agent.__using__/1`, `Jido.Agent.Extension`
- **must:** Extensions and Plugins use one provider contract: lower, normalize, verify, stable ID/version, and optional runtime support. Store provider data once in extensions. Validate the complete normalized definition. Authoring does not run handlers or start services.
- **why:** Extensions must use the same core definition contract.
- **kind:** functional
- **status:** active

### jido.agent.I23 — Error structure and application reasons

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.cmd/3`, `Jido.Agent.handle_signal/2`, `Jido.Agent.Turn.new/2`, `Jido.Agent.Codec.decode/2`, `Jido.Agent.Extension.lower/2`
- **must:** Built-in boundary faults have structured errors and nonempty messages. Retain routing targets and causes, execution callback codes, and caught callback causes. Message wording and extra diagnostic details can change. Preserve application-owned error reasons returned by Agent and Plugin callbacks.
- **why:** Callers need inspectable errors without losing application meaning.
- **kind:** functional
- **status:** active

### jido.agent.I24 — Raising boundaries

- **scope:** `Jido.Agent.define!/1`, `Jido.Agent.new!/1`, `Jido.Agent.instantiate!/2`, `Jido.Agent.complete_schema!/1`
- **must:** Bang constructors raise the returned validation error. Generated definition and schema accessors return their documented values or raise the corresponding validation error.
- **why:** Raising and tuple APIs must agree.
- **kind:** functional
- **status:** active

### jido.agent.I25 — Public entry points

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.__using__/1`, `Jido.Agent.cmd/3`
- **must:** Provide define/define! for definitions and instantiate/instantiate! for instances. Generated modules provide definition, schema, instantiate, cmd, and declared Signal helpers. Remove old new/new!, handle_signal, checkpoint, restore, and reflection wrappers without aliases.
- **why:** Refactoring must preserve supported entry points.
- **kind:** functional
- **status:** active

### jido.agent.I26 — One Agent composition definition

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.instantiate/2`
- **must:** The Agent is the sole composition unit. A leaf has %{agents: [], connections: []}. Instantiation retains the authored topology and checks copied child input bindings without process activation.
- **why:** Composition belongs to the enclosing Agent lifecycle.
- **kind:** functional
- **status:** active

### jido.agent.I27 — Common child declarations

- **scope:** `Jido.Agent.Topology`
- **must:** Immediate members name an Agent definition or module, a positive count or state-bound count, and copied initial state. Teams and leaves use the same signal input/output boundary. No groups or separate topology instances exist.
- **why:** A composed child uses the same Agent model as a plain child.
- **kind:** functional
- **status:** active

### jido.agent.I28 — Root and static references

- **scope:** `Jido.Agent.Topology`
- **must:** Root names the enclosing Agent output or input according to connection direction. Member endpoints name immediate agents only. State references are static data. Do not rewrite signal types or traverse nested addresses.
- **why:** Root behavior must be addressable without a second coordinator.
- **kind:** functional
- **status:** active

### jido.agent.I29 — Containment and imported identity

- **scope:** `Jido.Agent.Topology`
- **must:** Logical connections do not define process supervision, ownership, lifecycle, or implicit bus creation. Reject removed lifecycle and ownership declarations.
- **why:** A logical edge does not establish process containment or lifecycle authority.
- **kind:** functional
- **status:** active

### jido.agent.I30 — Group and delivery shape

- **scope:** `Jido.Agent.Topology`
- **must:** A counted destination requires explicit broadcast delivery. A single destination uses single delivery. No hidden worker selection policy is added.
- **why:** Group creation and delivery must have explicit, bounded intent.
- **kind:** functional
- **status:** active

### jido.agent.I31 — Explicit static includes

- **scope:** `Jido.Agent.Topology`
- **must:** Reuse composition through an Agent with its own routes and emissions. Reject static includes, exports, recursive paths, and separate group boundaries.
- **why:** Static composition reuse must not silently discard Agent behavior.
- **kind:** functional
- **status:** active

### jido.agent.I32 — Agent schedule declarations

- **scope:** `Jido.Agent.Extensions.Scheduling`
- **must:** The schedules block belongs to the Scheduling provider. Short and block forms lower to equal contribution data. No core schedules field or second Scheduler Plugin declaration is required.
- **why:** Scheduling is an Agent capability, independent of composition.
- **kind:** functional
- **status:** active

### jido.agent.I33 — Validated inert schedules

- **scope:** `Jido.Agent.Extensions.Scheduling`
- **must:** Validate unique names, one interval or cron expression, timezone, signal template, and an accepting input route. Do not install jobs or produce runtime identities during authoring.
- **why:** This boundary records intent without changing runtime behavior.
- **kind:** functional
- **status:** active

### jido.agent.I34 — Authoring document loss prevention

- **scope:** `Jido.Agent.Codec`
- **must:** Round-trip routes, topology, provider contributions, schema, metadata, identity, and complete state without loss. Use the same semantic validation for decoded data and plain Maps.
- **why:** The current format cannot represent the new authoring fields.
- **kind:** persisted-format
- **status:** active

### jido.agent.I35 — Authoring error locations

- **scope:** `Jido.Agent.Validation`, `Jido.Agent.DSL`
- **must:** Return structured paths for invalid fields and declarations. Raise compile-time errors for invalid DSL definitions, including related member and provider checks. Both authoring formats use the same semantic validator.
- **why:** Shared validation must retain useful diagnostics and one canonical result after extension lowering.
- **kind:** functional
- **status:** active


### jido.agent.I36 — Atomic composition changes

- **scope:** `Jido.Agent.cmd/3`, `Jido.Agent.mutate/2`
- **must:** Apply noun_verb data directives in order to one candidate. Validate complete next state and the final definition before acceptance. Preserve the source on any error. Return the accepted directives without process effects. State changes alone do not replace topology.
- **why:** Composition changes must be explicit value operations before persistence or process effects.
- **kind:** functional
- **status:** active

### jido.agent.I37 — One saved topology

- **scope:** `Jido.Persistence.snapshot/2`, `Jido.Persistence.restore/2`
- **must:** Save the complete accepted Agent definition and state once. Freeze nested module definitions into saved Agent values. Keep symbolic state bindings and logical connections. Restore the saved definition without looking up a newer authored definition or starting processes.
- **why:** A restored Agent must retain its accepted composition intent and custom callbacks must not silently omit it.
- **kind:** persisted-format
- **status:** active

### jido.agent.I38 — Checkpoint acceptance boundary

- **scope:** `Jido.Persistence.snapshot/2`, `Jido.Persistence.restore/2`
- **must:** Check the portable envelope and code reference manifest before custom state loading. Require exact identity and complete valid restored state. Custom callbacks convert state only. Contain malformed callback results and preserve application rejection reasons.
- **why:** Process handles and partial composition must not enter durable Agent data.
- **kind:** functional
- **status:** active

### jido.agent.I39 — Distinct format and code version

- **scope:** `Jido.Persistence.snapshot/2`, `Jido.Persistence.restore/2`, `Jido.Persistence.upgrade/3`
- **must:** Use snapshot format 1 and record fmt 4. Keep authored positive vsn, code fingerprints, and stored rev separate. Reject stale code references and unsupported legacy envelopes. Run an explicit upgrade Action to produce a new validated snapshot. Never infer a migration from a current definition.
- **why:** Storage format, deployed code, and saved instance revision have separate meanings.
- **kind:** persisted-format
- **status:** active

### jido.agent.I40 — One atomic saved revision

- **scope:** `Jido.Persistence.create_agent/3`, `Jido.Persistence.save_agent/3`, `Jido.Persistence.load_agent_with_revision/4`, `Jido.Persistence.delete_agent/4`
- **must:** Save complete accepted state and definition in one record under rev. Keep revision and expected_revision options. Reject stale or conflicting writes without changing stored bytes. Tombstones fence late writers. Each Agent has its own record.
- **why:** Recovery must not mix state from one accepted revision with composition from another.
- **kind:** persisted-format
- **status:** active

### jido.agent.I41 — Ordered topology edits

- **scope:** `Jido.Agent.mutate/2`, `Jido.Agent.Directive`
- **must:** Apply add, update, replace, and remove in batch order for agents, routes, and connections. Preserve unrelated fields and list order. Reject duplicate additions, missing selectors, identity edits, and malformed options. Support route reorder and full route/topology replacement.
- **why:** One Agent candidate is the authority for composition.
- **kind:** functional
- **status:** active

### jido.agent.I42 — Complete final composition graph

- **scope:** `Jido.Agent.Topology`, `Jido.Agent.mutate/2`
- **must:** Check final references after the complete batch. Reject missing endpoints, recursive containment, invalid state bindings, invalid counts, and excessive expansion. Allow logical connection cycles. Require broadcast for counted destinations. Reject removed ownership and lifecycle declarations.
- **why:** One Agent candidate is the authority for composition.
- **kind:** functional
- **status:** active

### jido.agent.I43 — Plugin declaration changes

- **scope:** `Jido.Agent.cmd/3`, Plugin change Directives
- **must:** Initialize only new Plugin state. Preserve existing state on compatible configuration. Require explicit state discard on removal and explicit migration on owned-key change. Keep unique Plugin, state, and Directive ownership. Reject changes combined with affected Plugin Directives.
- **why:** One Agent candidate is the authority for composition.
- **kind:** functional
- **status:** active

### jido.agent.I44 — Saved current Plugin declarations

- **scope:** `Jido.Persistence.snapshot/2`, `Jido.Persistence.restore/2`
- **must:** Save current provider contributions and code fingerprints with the accepted definition. Check fingerprints before Plugin state loading. Preserve removed or changed declarations as saved; never restore authored defaults over them.
- **why:** One Agent candidate is the authority for composition.
- **kind:** persisted-format
- **status:** active

### jido.agent.I45 — Stable accepted composition

- **scope:** `Jido.Agent.Topology.bind/2`
- **must:** Keep accepted definitions symbolic. Resolve copied child inputs and counts from the supplied current parent state without changing the definition or starting processes. Do not retain stale bound values across state changes. Reject eager, lazy, deferred, and ownership fields.
- **why:** One Agent candidate is the authority for composition.
- **kind:** functional
- **status:** active
