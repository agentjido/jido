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
  - Jido.Agent.Topology
  - Jido.Agent.Topology.Reference
  - Jido.Agent.Topology.Ref
  - Jido.Agent.Schedules
---

## Purpose

Protect Agent authoring, canonical definitions, instances, and direct commands.
The public DSL syntax stays unchanged. This contract refines the AGT, TURN,
EFFECT, PLUG, and ERROR entries in `guides/public-contracts.md`.

Agent-owned topology and schedule authoring are part of this component. They
remain declaration data. Activation, timer installation, schedule state seeding,
checkpoint/restore behavior, AgentServer, legacy Topology, persistence, and Directive
dispatch are outside this component. The module list selects implementation
mutation targets. It does not make internal functions public.

## Obligations

### jido.agent.I1 — Equivalent declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.new/1`, `Jido.Agent.Codec.decode/2`
- **must:** Equivalent supported module, map, keyword, and JSON declarations produce equal neutral definitions when module and version match.
- **why:** One canonical value must serve each authoring form.
- **kind:** functional
- **status:** active

### jido.agent.I2 — Neutral definitions

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.new/1`, `Jido.Agent.definition/1`
- **must:** A definition has nil identity and nil state. The definition constructor rejects identity-only, state-only, and instance values.
- **why:** Definition data must be reusable.
- **kind:** functional
- **status:** active

### jido.agent.I3 — Validated declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.new/1`
- **must:** Validate fields, versions, schemas, executable targets, and Plugin declarations. Reject unknown fields.
- **why:** Invalid declarations must fail before execution.
- **kind:** functional
- **status:** active

### jido.agent.I4 — Duplicate policies

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.new/1`, `Jido.Agent.set/2`, `Jido.Agent.__using__/1`
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

- **scope:** `Jido.Agent.define!/1`, `Jido.Agent.new!/1`, `Jido.Agent.instantiate!/2`, `Jido.Agent.complete_schema!/1`
- **must:** Bang constructors raise the returned validation error. Generated definition and schema accessors return their documented values or raise the corresponding validation error.
- **why:** Raising and tuple APIs must agree.
- **kind:** functional
- **status:** active

### jido.agent.I25 — Public entry points

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.new/1`, `Jido.Agent.instantiate/2`, `Jido.Agent.__using__/1`, `Jido.Agent.cmd/3`
- **must:** Provide define/1 and define!/1 for neutral definitions and generated instantiate/0,1 and instantiate!/0,1 for instances. Retain the listed public function names and arities. Top-level new/new! wrap definition construction; generated new/new! wrap instance construction with unchanged results, defaults, and errors. Internal compiler and runtime structures are outside this promise.
- **why:** Refactoring must preserve supported entry points.
- **kind:** functional
- **status:** active

### jido.agent.I26 — One Agent composition definition

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`, `Jido.Agent.instantiate/2`
- **must:** Store optional topology intent on the canonical Agent. A plain Agent has nil topology. Preserve the composition collections without a member wrapper, default input schema, or separate topology constructor, instance, or activation API. Instantiation retains declarations without resolving child sources or state references.
- **why:** Composition belongs to the enclosing Agent lifecycle.
- **kind:** functional
- **status:** active

### jido.agent.I27 — Common child declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Agent, group, and child entries require exactly one module or neutral Agent definition. Retain the normalized neutral child definition, including in static includes. Preserve initial state and eager, lazy, or deferred process startup intent. Child entries use the child Agent as root behavior, without a separate director or input lifecycle.
- **why:** A composed child uses the same Agent model as a plain child.
- **kind:** functional
- **status:** active

### jido.agent.I28 — Root and static references

- **scope:** `Jido.Agent.__using__/1`, `Jido.Agent.define/1`
- **must:** Allow the enclosing Agent as a root endpoint in relationships, connections, and exports without adding a member. Keep root, state, input, member, and included-export references as static data. Scope topology helpers to the topology block and reject malformed endpoint references. Keys are nonempty atom or UTF-8 string values of at most 255 bytes. Atom and string spellings share one identity for uniqueness and self-ownership checks.
- **why:** Root behavior must be addressable without a second coordinator.
- **kind:** functional
- **status:** active

### jido.agent.I29 — Containment and imported identity

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Record owned or independent containment separately from logical parent-exit policy. Imported Agent endpoints retain validated stable Agent Refs and do not become created or adopted members.
- **why:** A logical edge does not establish process containment or lifecycle authority.
- **kind:** functional
- **status:** active

### jido.agent.I30 — Group and delivery shape

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Accept non-negative fixed counts or state/input sources, or keyed member lists with stable unique keys. Reject conflicting count/members, invalid key_by, and duplicate declaration keys. Preserve member order and zero counts. Apply count one only when count and members are absent. Known local and included group exports require explicit one or broadcast delivery; known single-Agent exports reject group delivery mode. Unresolved export kinds remain binding intent with validated delivery shape.
- **why:** Group creation and delivery must have explicit, bounded intent.
- **kind:** functional
- **status:** active

### jido.agent.I31 — Explicit static includes

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Includes accept explicit composition maps with validated declaration shape and preserve parameter mappings and bindings. Reject implicit extraction from an Agent module, definition, or instance. Do not create an included root Agent.
- **why:** Static composition reuse must not silently discard Agent behavior.
- **kind:** functional
- **status:** active

### jido.agent.I32 — Agent schedule declarations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`, `Jido.Agent.instantiate/2`
- **must:** Equivalent DSL, map, and keyword schedules yield equal ordered declarations on the Agent. Required, optional, and defaulted fields preserve literal values without treating user tuples as internal presence markers. Require the Scheduler Plugin. A plain Agent can declare schedules with nil topology. Instance options cannot replace schedules.
- **why:** Scheduling is an Agent capability, independent of composition.
- **kind:** functional
- **status:** active

### jido.agent.I33 — Validated inert schedules

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`, `Jido.Agent.instantiate/2`
- **must:** Require unique keys and exactly one valid bounded interval or cron expression. Validate cron timezone, portable type/data templates, delivery mode, explicit durable generations, and skip-only missed-occurrence policy. Reject fixed envelope identities and unsupported targets. Preserve exact template data. Authoring and instantiation do not install jobs or seed Scheduler job state; declaration templates have no generated identity or time.
- **why:** This boundary records intent without changing runtime behavior.
- **kind:** functional
- **status:** active

### jido.agent.I34 — Authoring document loss prevention

- **scope:** `Jido.Agent.Codec.encode/1`, `Jido.Agent.Codec.encode/2`
- **must:** Reject non-nil topology or nonempty schedule declarations in the existing document format. Continue encoding supported plain definitions. Do not silently drop new declaration data.
- **why:** The current format cannot represent the new authoring fields.
- **kind:** persisted-format
- **status:** active

### jido.agent.I35 — Authoring error locations

- **scope:** `Jido.Agent.define/1`, `Jido.Agent.__using__/1`
- **must:** Keep structured field paths for invalid declaration options. When compiler annotations are enabled, DSL errors identify the source field or declaration, including topology entries, schedules, included maps, and nested bindings. Agent extensions can lower authored composition before final Agent validation; invalid lowered data still fails at that validation boundary.
- **why:** Shared validation must retain useful diagnostics and one canonical result after extension lowering.
- **kind:** functional
- **status:** active
