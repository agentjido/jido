---
modules:
  - Jido.Agent
  - Jido.Agent.Authoring.Compiler
  - Jido.Agent.DSL.Macros
  - Jido.Agent.Authoring
  - Jido.Agent.Authoring.Extension
  - Jido.Agent.Authoring.SourceMap
  - Jido.Agent.Extension
  - Jido.Agent.Source
  - Jido.Agent.Validation
  - Jido.Agent.State
  - Jido.Agent.Codec
  - Jido.Plugin.Codec
  - Jido.Agent.Runner
  - Jido.Agent.Turn
  - Jido.Agent.Plugin
  - Jido.Agent.Plugin.Pipeline
  - Jido.Agent.Interface
  - Jido.Agent.Callback
---

## Purpose

Protect Agent authoring, canonical definitions, instances, and direct commands.
The public DSL syntax stays unchanged. This contract refines the AGT, TURN,
EFFECT, PLUG, and ERROR entries in `guides/public-contracts.md`.

Checkpoint/restore behavior, AgentServer, Topology, persistence, and Directive
dispatch are outside this component. The module list selects implementation
mutation targets. It does not make internal functions public.

## Obligations

### jido.agent.I1 — Equivalent declarations

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.Codec.decode/2`
- **must:** Equivalent supported module, map, keyword, and JSON declarations produce equal neutral definitions when module and version match.
- **why:** One canonical value must serve each authoring form.
- **kind:** functional
- **status:** active

### jido.agent.I2 — Neutral definitions

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.definition/1`
- **must:** A definition has nil identity and nil state. The definition constructor rejects identity-only, state-only, and instance values.
- **why:** Definition data must be reusable.
- **kind:** functional
- **status:** active

### jido.agent.I3 — Validated declarations

- **scope:** `Jido.Agent.new/1`
- **must:** Validate fields, versions, schemas, executable targets, and Plugin declarations. Reject unknown fields.
- **why:** Invalid declarations must fail before execution.
- **kind:** functional
- **status:** active

### jido.agent.I4 — Duplicate policies

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.set/2`, `Jido.Agent.__using__/1`
- **must:** Data keyword inputs keep the last duplicate value. DSL option duplicates fail compilation.
- **why:** Each language has an explicit duplicate policy.
- **kind:** functional
- **status:** active

### jido.agent.I5 — Stable reusable values

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.instantiate/2`
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
- **must:** Accept only identity and state overrides. An absent identity produces a fresh nonempty string. Reject invalid supplied identities.
- **why:** Identity belongs to the instance.
- **kind:** functional
- **status:** active

### jido.agent.I8 — Initialization defaults

- **scope:** `Jido.Agent.instantiate/2`
- **must:** Apply and validate static defaults during initialization under Zoi input rules: nil activates an explicit default. Preserve supplied false and zero. Preserve permitted nil when no replacing default applies; stored state keeps permitted nil without reapplying defaults.
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

- **scope:** `Jido.Agent.handle_signal/2`, `Jido.Agent.cmd/3`
- **must:** Select one Action or Flow in Router order. A custom selection cannot replace the original source Signal.
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
- **must:** Return a complete valid candidate and ordered valid Directives. Keep definition and identity.
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

- **scope:** `Jido.Agent.Codec.encode/1`, `Jido.Agent.Codec.decode/2`
- **must:** Use version-2 static definition documents, omit instance identity/state, resolve code through a trusted Registry, and enforce document bounds.
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

- **scope:** `Jido.Agent.__using__/1`, `Jido.Agent.Extension.lower/3`
- **must:** Evaluate computed options once. Apply extensions in order once, consume their entities, and validate lowered core configuration.
- **why:** Extensions must use the same core definition contract.
- **kind:** functional
- **status:** active

### jido.agent.I23 — Error structure and application reasons

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.cmd/3`, `Jido.Agent.handle_signal/2`, `Jido.Agent.Turn.new/2`, `Jido.Agent.Codec.decode/2`, `Jido.Agent.Extension.lower/3`
- **must:** Built-in boundary faults have structured errors and nonempty messages. Retain routing targets and causes, execution callback codes, and caught callback causes. Message wording and extra diagnostic details can change. Preserve application-owned error reasons returned by Agent and Plugin callbacks.
- **why:** Callers need inspectable errors without losing application meaning.
- **kind:** functional
- **status:** active

### jido.agent.I24 — Raising boundaries

- **scope:** `Jido.Agent.new!/1`, `Jido.Agent.instantiate!/2`, `Jido.Agent.complete_schema!/1`
- **must:** Bang constructors raise the returned validation error. Generated definition and schema accessors return their documented values or raise the corresponding validation error.
- **why:** Raising and tuple APIs must agree.
- **kind:** functional
- **status:** active

### jido.agent.I25 — Public entry points

- **scope:** `Jido.Agent.new/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.cmd/3`
- **must:** Retain the listed public function names and arities, including generated module functions. Internal compiler and runtime structures are outside this promise.
- **why:** Refactoring must preserve supported entry points.
- **kind:** functional
- **status:** active

