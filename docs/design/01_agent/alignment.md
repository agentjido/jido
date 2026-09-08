# Agent seam alignment plan

> Planning document. This document is pending approval. Code in `lib` is the
> source of truth for current behavior.

## 1. Purpose, scope, and seam owner

This document gives an ordered plan for the `01_agent` seam. The plan aligns
the current Agent implementation with an approved target contract. It does not
change the current contract by itself.

`Jido.Agent` owns these items:

- the immutable Agent definition and instance values;
- Agent construction and validation;
- the domain schema, normalized routes, Plugins, and metadata on an Agent;
- separate domain state and Plugin state validation and immutable changes;
- direct command evaluation at the Agent entry point;
- Agent checkpoint and restore callbacks.

This seam does not own these items:

- Action, Flow, and executable rules, which belong to `jido_action`;
- Signal and Router matching rules, which belong to `jido_signal`;
- cross-system Turn order, which belongs to `00_overview` and
  `04_turn-evaluation`;
- stable runtime identity, which belongs to `03_agent-identity`;
- Plugin callback and runtime rules, which belong to `05_plugins`;
- commit and persistence record rules, which belong to later seams;
- the public error taxonomy and portable-term error shape, which belong to
  `12_errors-and-contracts`.

The plan keeps current public behavior unless a phase gives a migration path
and evidence for the change.

## 2. Inputs reviewed

### Design inputs

The review used these local design rules:

- `docs/design/AGENTS.md`
- `docs/design/README.md`

The review used all documents in the Agent seam:

- `docs/design/01_agent/README.md`
- `docs/design/01_agent/agent.md`
- `docs/design/01_agent/gap-analysis.md`

The review used all documents in the required prerequisite seams:

- `docs/design/00_overview/README.md`
- `docs/design/00_overview/architecture.md`
- `docs/design/00_overview/invariants.md`
- `docs/design/00_overview/glossary.md`
- `docs/design/00_overview/gap-analysis.md`
- `docs/design/90_package-boundaries/README.md`
- `docs/design/90_package-boundaries/runtime-extension-boundaries.md`
- `docs/design/90_package-boundaries/gap-analysis.md`
- `docs/design/12_errors-and-contracts/README.md`
- `docs/design/12_errors-and-contracts/errors.md`
- `docs/design/12_errors-and-contracts/gap-analysis.md`

No prerequisite alignment document exists.

### Canonical code inputs

The review used these Agent modules:

- `lib/jido/agent.ex`
- `lib/jido/agent/authoring.ex`
- `lib/jido/agent/builder.ex`
- `lib/jido/agent/codec.ex`
- `lib/jido/agent/codec/data.ex`
- `lib/jido/agent/codec/deriver.ex`
- `lib/jido/agent/codec/registry.ex`
- `lib/jido/agent/command.ex`
- `lib/jido/agent/command/runner.ex`
- `lib/jido/agent/interface.ex`
- `lib/jido/agent/state.ex`
- `lib/jido/agent/turn.ex`
- `lib/jido/agent/validation.ex`

The review also used these direct integration modules:

- `lib/jido/plugin.ex`
- `lib/jido/plugin/spec.ex`
- `lib/jido/portable_term.ex`
- `lib/jido/persistence.ex`
- `lib/jido/agent_server.ex`
- `lib/jido/agent_server/state.ex`
- `lib/jido/agent_server/runtime_checkpoint.ex`

The public module documentation in these files is part of the current
evidence. In particular, the documentation for `Jido.Agent`,
`Jido.Agent.Builder`, `Jido.Agent.Codec`, `Jido.Agent.Command`,
`Jido.Agent.Turn`, and `Jido.Plugin` states supported behavior.

### Test inputs

The review used these focused tests:

- `test/jido/agent_test.exs`
- `test/jido/agent/authoring_contract_test.exs`
- `test/jido/agent/builder_test.exs`
- `test/jido/agent/codec_test.exs`
- `test/jido/agent/schema_test.exs`
- `test/jido/agent/serialization_contract_test.exs`
- `test/jido/agent/validation_test.exs`
- `test/jido/plugin/contract_test.exs`
- `test/jido/persistence/checkpoint_portability_test.exs`
- `test/examples/99_research/99_09_route_selection/route_selection_test.exs`
- `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs`
- `test/examples/99_research/99_15_state_migration/state_migration_test.exs`

The review did not run tests because this task changes planning documents only.

## 3. Prerequisite status, assumptions, and blockers

### Current prerequisite status

| Prerequisite seam | Status | Effect on this plan |
| --- | --- | --- |
| `00_overview` | No alignment document. All documents are pending approval. | The route order, Plugin preparation order, and shared public value set are not final. |
| `90_package-boundaries` | No alignment document. All documents are pending approval. | Core ownership, durable value types, migration ownership, and external package contracts are not final. |
| `12_errors-and-contracts` | No alignment document. All documents are pending approval. | Stable error classes, codes, fields, normalization, and portable-term path format are not final. |

This Agent plan does not approve a contract that one of these prerequisite
seams owns.

### Assumptions for review

The following assumptions let the plan be specific. Each assumption needs
review in its owner seam.

- **A-01, current API stability:** Supported Agent APIs stay public during the
  V3 alignment. This includes neutral definitions, Builder, Codec, `to_map/1`,
  `set/2`, custom `handle_signal/2`, checkpoint callbacks, restore callbacks,
  and direct `cmd/3`.
- **A-02, package ownership:** Jido core continues to own the Agent value and
  its checkpoint policy. `jido_action` continues to own executable behavior.
  `jido_signal` continues to own route matching.
- **A-03, route policy:** The current exactly-one route rule and prepared-Signal
  route order stay in effect until `00_overview` and `04_turn-evaluation`
  approve another rule. This is a temporary compatibility assumption. It is
  not a new cross-system decision.
- **A-04, error policy:** New Agent checks use the error class and stable code
  that `12_errors-and-contracts` approves. Until then, the current error results
  stay canonical.
- **A-05, portable state:** `12_errors-and-contracts` will require recursive
  portable-term validation before a value becomes valid Agent state. It will
  define the path format and stable error code.
- **A-06, identity:** An Agent instance keeps its nonempty binary `id`. A future
  Agent Ref can include that ID, but this seam does not define namespace,
  partition, lookup, or storage identity.
- **A-07, revision limit:** A definition revision identifies a module-owned
  definition. It does not pin loaded BEAM code for one Turn. Complete code
  pinning needs decisions in `jido_action`, Turn evaluation, and live upgrade
  seams.
- **A-08, Plugin state key:** A stateful Plugin continues to define its state
  atom and schema through `state_spec/1`. The Plugin seam can refine the
  callback, but it must preserve one unique atom key for each stateful Plugin.

### Blockers

- **B-01:** Do not change route selection or Plugin preparation order before
  the overview and Turn owners approve one rule.
- **B-02:** Do not expose new stable Agent error results before the error seam
  approves their class, code, fields, and path format.
- **B-03:** Do not require a public `%Jido.Agent.Checkpoint{}` before the package
  and persistence owners approve durable public values and migration ownership.
- **B-04:** Do not make module-only definitions mandatory before the authoring
  seam gives Builder, Codec, direct definitions, and behavior-only modules a
  migration path.
- **B-05:** Do not claim that a definition revision pins Action or Flow code.
  The present executable boundary cannot prove that claim.

These blockers do not prevent compatible documentation work, test inventory
work, or the approved separation of domain state and Plugin state.

## 4. Retained implemented baseline

The following items are current facts that the alignment plan keeps. The plan
does not keep the current location of Plugin state. T-03 defines that change.

- **RB-01:** One `%Jido.Agent{}` type has two valid forms. A neutral definition
  has `id: nil` and `state: nil`. An instance has a nonempty string ID and a
  validated plain state map. The definition and instance distinction stays.
- **RB-02:** `new/1`, `instantiate/2`, `definition/1`, `definition?/1`,
  `instance?/1`, `validate_definition/1`, and `validate_instance/1` make the two
  forms explicit.
- **RB-03:** `new/2` and generated module constructors create an instance from
  module-owned static configuration. Instance overrides are limited to
  identity and state data.
- **RB-04:** The Agent stores a normalized domain schema, Plugin declarations,
  routes, and metadata.
- **RB-05:** Each stateful Plugin defines one atom key and one state schema.
  Plugin keys are unique in one Agent. The plan keeps this ownership rule and
  moves each value to `agent.plugin_state`.
- **RB-06:** `set/2` deep-merges domain fields only. Internal transition logic
  validates immutable replacements. The plan keeps these roles and adapts them
  to two state maps.
- **RB-07:** During a command, an executable cannot change Plugin-owned state.
  Each stateful Plugin can update only its own complete state value. The plan
  makes this separation structural instead of using keys in the domain map.
- **RB-08:** `cmd/3` is a direct immutable evaluation API. It returns a candidate
  Agent and Directives. It starts no Server, commits no live state, and
  dispatches no Directive.
- **RB-09:** Direct and live execution share
  `Jido.Agent.Command.Runner`. The Server owns the commit revision and keeps it
  separate from the Agent value.
- **RB-10:** Custom `handle_signal/2` is a supported routing boundary. The
  default handler requires exactly one Router target after Plugin preparation.
- **RB-11:** `checkpoint/2` and `restore/3` are supported. Their module callbacks
  are optional and overridable. The default checkpoint is a plain version 1
  map and supports direct definitions and behavior-only modules.
- **RB-12:** Builder and Codec are supported authoring forms. Codec data is
  versioned and uses a trusted Registry. It is separate from checkpoint data.
- **RB-13:** The Agent contains no runtime PID, timer, task, monitor, or runtime
  handle.
- **RB-14:** The persistence layer checks a complete record for portable terms.
  Agent construction and transition do not yet perform this check.

## 5. Target Agent contract

This section is the recommended end state for this seam. It is a proposal.
Items that depend on another seam have an assumption or blocker label.

### T-01. Keep the two valid Agent forms

`%Jido.Agent{}` continues to represent a neutral definition and an instance.
Definitions and instances remain complete for their own form. Half-instances
remain invalid.

A neutral definition has `id: nil`, `state: nil`, and `plugin_state: nil`. An
instance has a nonempty binary ID, a domain `state` map, and a `plugin_state`
map.

The public definition and instance functions in RB-02 stay supported. Module
constructors stay thin delegates to `Jido.Agent.new/2`.

### T-02. Keep one normalized static definition

A definition contains the Agent module, name, description, domain schema,
ordered Plugin declarations, ordered normalized routes, metadata, and the
optional definition revision from T-07.

Only `id`, `state`, and `plugin_state` differ between a definition and its
instances. Normalization continues to validate Plugin declarations and
executable targets. It validates the domain schema and each Plugin state schema
as separate schema boundaries.

### T-03. Separate domain state and Plugin state

Add `plugin_state` to `%Jido.Agent{}`. `agent.state` contains domain state only.
`agent.plugin_state` contains Plugin-owned state only.

Each stateful Plugin continues to define its state with `state_spec/1`:

```elixir
@impl Jido.Plugin
def state_spec(_opts), do: {:scheduler, scheduler_state_schema()}
```

The first tuple value is the Plugin state key. It must be an atom. It must not
be `nil` or `:__struct__`. Each stateful Plugin in one Agent must have a unique
key. A stateless Plugin returns `:none` and has no entry.

The Agent state then has this shape:

```elixir
%Jido.Agent{
  state: %{status: :pending, total: 100},
  plugin_state: %{
    scheduler: %{cron: %{}}
  }
}
```

The domain schema validates only `state`. Each Plugin schema validates only its
value under `plugin_state[plugin_key]`. Construction applies defaults to both
state classes. The Agent validates both maps before it accepts one candidate.
Every stateful Plugin has exactly one entry after construction. The entry value
can be any value that its schema accepts. It does not have to be a map.
The outer map accepts only declared stateful Plugin keys. It rejects unknown
keys and entries for stateless Plugins.

Domain keys and Plugin keys use different namespaces. The same atom can exist
in both maps. Plugin keys still must be unique among Plugins.

A domain root refinement sees domain state only. A Plugin schema sees its own
value only. A schema does not validate a relation between domain state and
Plugin state. Command logic must make any cross-state rule explicit before
Jido validates and assembles the candidate.

For one compatibility period, instance construction accepts the old combined
`state` input. It uses the declared Plugin keys to split that map. If explicit
`plugin_state` is present, the old `state` input must contain no declared
Plugin key. Otherwise, construction returns a validation error. New code must
use separate inputs.

Temporary `Jido.Agent.migrate_combined_state/1` converts an old Agent struct or
map to the split shape. It uses normalized Plugin declarations to move known
Plugin keys. It validates both results and returns a tagged result. Remove this
helper only through the approved compatibility policy.

This target does not require a public `%Jido.Plugin{}` configuration value.
The current ordered `{module, options}` declarations stay supported.

### T-04. Give each state class explicit operations

Keep `set/2` as the public domain patch operation. It deep-merges only
`agent.state` and cannot change `agent.plugin_state`.

Add these explicit data operations:

| Function | Result |
| --- | --- |
| `state/1` | Returns the complete domain state map. |
| `fetch_state/2` | Uses `Map.fetch/2` semantics on domain state. |
| `plugin_state/2` | Uses `Map.fetch/2` semantics to return the complete value for one Plugin key. |
| `fetch_plugin_state/3` | Uses `Map.fetch/2` on one Plugin value when that value is a map. It returns `:error` for a missing key or a non-map value. |
| `replace_state/2` | Replaces and validates the complete domain state. |
| `replace_plugin_state/3` | Replaces and validates one complete Plugin state value. |

`replace_plugin_state/3` rejects an unknown key and a stateless Plugin key. It
does not run a command or produce Directives. All operations return a new Agent
when they change data.

Internal candidate assembly replaces both maps together. Add an internal
`transition/3` or an equivalent private value operation for that purpose.
During the compatibility period, `transition/2` accepts the old complete
combined replacement, splits it by declared Plugin keys, and delegates to the
two-map operation. New domain-only replacement uses `replace_state/2`.

Keep `complete_schema/1` for the compatibility period as the schema for old
combined input. Mark it as a migration helper. It is not the schema of the new
live `state` field. Add a Plugin-state schema helper for the new
`plugin_state` map.

### T-05. Keep direct command evaluation

`cmd/3` remains a supported direct API. Direct and live commands continue to
use the same Runner for preparation and candidate assembly. The return remains
`{:ok, agent, directives}` or an error tuple.

The executable receives domain state only in `context.agent_state`. Its output
is a complete domain state map. It cannot read or return Plugin state through
that field. Plugin reduction starts from `agent.plugin_state`. Each Plugin
receives only its own value and can replace only that value. Jido assembles the
domain result and all Plugin results into one candidate Agent.

Only the live Agent Server can commit the candidate or dispatch Directives.
The Agent value does not contain the Server state version.

### T-06. Keep route behavior stable until its owners decide

Custom `handle_signal/2` remains supported. The current default route behavior
stays canonical while B-01 is open.

If the overview and Turn seams approve source-Signal selection and first-match
precedence, implement that as a later cross-seam phase. The change must cover
direct commands, live admission, Plugin preparation, custom callbacks, route
predicates, and migration tests. Approval of this Agent plan alone does not
approve that route change.

### T-07. Add a compatible definition revision

Add `definition_revision` to the Agent static definition. Its type is `nil` or
a positive integer.

- A module that uses `Jido.Agent` gets revision `1` when it does not declare a
  value. This keeps existing module source compatible.
- A module can declare a positive revision and gets a generated
  `definition_revision/0` accessor.
- Direct neutral definitions and behavior-only modules can keep `nil`.
- Builder and Codec must preserve this field.
- The revision is part of normalized static definition equality.
- The author must increase the revision when static configuration or routed
  behavior changes.
- The revision is not the Agent Server state version or persistence storage
  version.

For static equality, validate both neutral definitions through the canonical
validator and compare `Agent.definition(agent) === module.agent()`. This strict
comparison includes `module`, `name`, `description`, `schema`, `plugins`,
`routes`, `metadata`, and `definition_revision`. It excludes `id` and `state`.
It also excludes `plugin_state`. Do not use a hash as the source of truth.

The revision gives restore a clear compatibility gate. It does not detect a
code change when an author fails to increase the value. See A-07 and B-05.

### T-08. Evolve checkpoints without removing current support

Keep the public `checkpoint/2` and `restore/3` entry points and their context
maps. Keep custom callbacks during V3.

Add a default checkpoint map version 2 after T-07:

```elixir
%{
  version: 2,
  kind: :agent,
  agent_module: MyApp.Agent,
  definition_revision: 3,
  id: "agent-1",
  state: %{status: :pending},
  plugin_state: %{scheduler: %{cron: %{}}}
}
```

For a versioned module-owned Agent, checkpoint creation must compare the
complete normalized static definition with the current module definition by
strict equality. Restore must require the saved module and revision. It then
builds static configuration from the current module. It validates saved domain
state and each saved Plugin state value separately.

Restore must continue to read the current default version 1 map. Version 1
uses current restore behavior and makes no revision guarantee. During version
1 restore, Jido uses the declared Plugin keys to split the old combined state
map. Direct definitions and behavior-only modules keep their
embedded-definition path.

Custom callback maps remain supported. A custom callback that saves Plugin
state must change its payload to save `agent.plugin_state` separately. Custom
maps do not claim the new core revision guarantee unless they return the
approved version 2 fields. The persistence owner must decide if it later wraps
custom payloads in a core envelope. This is part of B-03.

Do not add a public Checkpoint struct in this phase.

### T-09. Validate portable state before it becomes an Agent candidate

Subject to A-05 and B-02, validate `agent.state` and `agent.plugin_state` at
these points:

- instance construction;
- domain and Plugin replacement, including `set/2`;
- internal two-map candidate assembly;
- direct and live candidate assembly;
- default checkpoint construction;
- restore before the Agent becomes valid.

The check must reject PIDs, ports, references, functions, improper lists, and
non-byte-aligned bitstrings at any depth. It must report the first failing path
under `[:state]` or `[:plugin_state, plugin_key]` in the format that the error
seam approves.

Keep the persistence record check as defense in depth. Do not apply the
instance-state rule to static module configuration. Static route matches can
contain approved external function captures.

### T-10. Use approved errors without an interim error model

Current errors stay canonical while B-02 is open. New revision, static-match,
portable-state, checkpoint-version, and restore failures must use the class,
code, fields, and normalization rules that `12_errors-and-contracts` approves.

Do not add new raw atoms or tuples as an interim public contract.

### T-11. Keep authoring and runtime values separate

Builder and Codec continue to produce or transport neutral definitions. Codec
documents remain trusted-Registry authoring data. Checkpoints continue to
transport instance recovery data. Neither format becomes the other format.

Agent definitions and instances remain free of runtime handles. `to_map/1`
includes separate `state` and `plugin_state` fields for an instance.

## 6. Alignment decisions

| Conflict | Decision | Reason | Migration effect |
| --- | --- | --- | --- |
| The proposal removes neutral definitions. Current code supports them. | **Retain** neutral definitions and instance separation. | Builder, Codec, direct definitions, tests, and public module documentation use this contract. | No source migration. Later module-only proposals must be additive. |
| The proposal adds a separate `plugin_state` field. Current code uses one state map. | **Change** to separate domain and Plugin state as defined in T-03. | Key protection in one map is not a sufficient ownership boundary. Separate maps give Actions and Plugins separate data contracts. | Split old combined input and version 1 checkpoints by declared Plugin keys. Update Actions, Plugins, checkpoints, persistence, and Servers in one release unit. |
| The proposal replaces `set/2` and internal `transition/2`. | **Change in stages** as defined in T-04. Keep `set/2` for domain patches. Add explicit access and replacement functions. Adapt internal transition to both maps. | Separate state classes need unambiguous operations. Existing domain patches must keep working. | Existing `set/2` call sites stay valid. Callers that read Plugin keys from `agent.state` move to `agent.plugin_state`. Internal callers migrate to two-map candidate assembly. |
| The proposal selects the first route before Plugin preparation. Current code requires one route after preparation. | **Defer** the change under B-01. | This is a cross-system Turn decision. The prerequisite owner is not aligned. | Current direct and live behavior stays stable. A later change needs one explicit compatibility release. |
| The proposal removes custom `handle_signal/2`. | **Retain** the callback. | It is a supported routing boundary with focused tests. | Existing custom routing modules continue to work. A later restricted form needs deprecation evidence. |
| The proposal fixes checkpoint shape and removes callback overrides. | **Change in stages** with T-08. Keep callbacks and version 1 restore. Add a version 2 default map for versioned modules. | Existing callbacks and direct definitions are supported. Revision checks still need a new default format. | Old maps remain readable. New versioned modules write version 2. Custom maps keep their current path. |
| The proposal removes Builder, Codec, and `to_map/1`. | **Retain** all three. | They are current public authoring and inspection contracts. No evidence supports removal. | Codec adds a compatible revision field and keeps version 1 decode. |
| The proposal restores only from current module configuration. Current code can restore embedded definitions. | **Change in stages** with T-08. Use strict module restore only for versioned module-owned checkpoints. | Strict restore is useful for module-owned definitions. Direct and behavior-only definitions still need their current path. | Version 1 and unversioned restore stay compatible. Version 2 module restore can fail on revision mismatch. |
| The proposal requires a positive definition revision for every Agent. Current code has none. | **Change** to the optional compatible model in T-07. | A mandatory revision would remove direct and behavior-only definitions without a migration. | Existing module authors get revision 1. Direct definitions can remain unversioned. |
| The proposal adds a public Checkpoint struct. Current code uses maps. | **Defer** under B-03. | The package and persistence seams have not approved durable public values. | No struct conversion now. Map versions provide a smaller migration. |
| The proposal adds separate state getter and replacement APIs. | **Change** by adding the functions in T-04. | The separate maps give each function one clear meaning. | Direct struct access stays possible. New code gets stable state boundaries. |
| Current `complete_schema/1` builds one combined schema. | **Retain for migration** and add a new Plugin-state schema helper. | Old combined input and checkpoints need the current schema during conversion. The new live fields need separate validation. | Mark `complete_schema/1` as a legacy-input helper for the compatibility period. Do not use it to validate new live state. |
| Current domain root refinements receive Plugin-owned fields after schema composition. | **Change** to domain-only root refinement. | A domain schema must not depend on Plugin storage layout. Each Plugin schema validates its own value. | A root refinement that reads a Plugin key must move that rule into command logic or the owning Plugin. |
| Portable checks run only at persistence today. | **Change** after A-05 and B-02 are resolved. | A nonpersistent Agent must not accept runtime handles in domain state or Plugin state. | Some permissive `Zoi.any()` states will become invalid. Release notes must list rejected terms. |
| Public checkpoint documentation calls current state domain-only. | **Change** the documentation in the first implementation phase and again with the split. | Version 1 contains combined state. Version 2 has separate `state` and `plugin_state` fields. | No runtime effect in the documentation phase. Migration text must identify both formats. |
| Direct Agent execution could be removed in favor of Servers. | **Retain** direct `cmd/3`. | It is a tested pure evaluation boundary and does not claim commit. | No migration. Server execution continues to share the Runner. |
| New checks need new error meanings. | **Defer** exact public shapes to `12_errors-and-contracts`. | That prerequisite owns taxonomy and stable codes. | Tests must use the approved codes when they exist. |

## 7. Ordered implementation plan

### Phase 0. Approve prerequisite decisions

**Contract changes**

- No runtime contract changes.
- Approve or replace assumptions A-02 through A-08.
- Record the route rule in the overview and Turn seams.
- Record new Agent error meanings in the error seam.

**Likely code areas**

- No code changes.
- Design documents in `00_overview`, `04_turn-evaluation`,
  `12_errors-and-contracts`, and `90_package-boundaries`.

**Compatibility or migration work**

- Define one release boundary for any route change.
- Define whether custom checkpoint payloads need a core persistence envelope.

**Verification**

- Each prerequisite has an approved alignment document.
- Each assumption in this document has an approved owner decision.

**Exit criteria**

- B-01 through B-05 are resolved or accepted as explicit deferrals.
- No Agent implementation phase depends on an undefined error or route rule.

### Phase 1. Lock and document the retained baseline

**Contract changes**

- No behavior change.
- Correct checkpoint documentation so it says complete Agent state.
- Document neutral definitions, Builder, Codec, callbacks, and direct execution
  as retained V3 contracts.
- Document the current combined state as the migration source, not the target.

**Likely code areas**

- Public documentation in `lib/jido/agent.ex`.
- Agent guides and API migration tables.
- Focused contract test names and comments where wording is inaccurate.

**Compatibility or migration work**

- None.

**Verification**

- Run the current Agent, Builder, Codec, schema, Plugin contract, and
  serialization contract tests.
- Add a public API inventory assertion if the current suite does not give a
  stable inventory.

**Exit criteria**

- Public documentation and tests clearly separate the current combined state
  shape from the approved split target.
- No supported Agent API is marked for removal.

### Phase 2. Add the compatible definition revision

**Contract changes**

- Implement T-07.
- Add the revision to normalized definition equality and `to_map/1`.
- Add the generated module accessor.

**Likely code areas**

- `lib/jido/agent.ex`
- `lib/jido/agent/validation.ex`
- `lib/jido/agent/builder.ex`
- Agent DSL compiler and authoring modules under `lib/jido/agent/dsl`
- `lib/jido/agent/codec.ex`
- `lib/jido/agent/codec/deriver.ex`
- `lib/jido/agent/codec/registry.ex`

**Compatibility or migration work**

- Default existing `use Jido.Agent` modules to revision 1.
- Let direct definitions and behavior-only modules use `nil`.
- Encode a new Agent authoring document version with the revision.
- Continue to decode version 1 documents as unversioned definitions.

**Verification**

- Add tests for default revision 1, explicit positive revisions, invalid
  revisions, direct unversioned definitions, Builder preservation, Codec
  version 1 decode, Codec new-version round trip, and `to_map/1`.
- Enable the non-restore part of the definition revision research example.

**Exit criteria**

- Every existing module compiles without a source change.
- Existing Codec documents still decode.
- Definition and Server state revisions cannot be confused by name or type.

Phases 3 through 7 are one release unit. Do not publish an intermediate state
shape. Keep the full package test suite green in each phase with private
compatibility adapters. Remove those adapters before Phase 7 exits.

### Phase 3. Add the split Agent value and migration parser

**Contract changes**

- Add `plugin_state` to the Agent schema and struct.
- Make a definition require `state: nil` and `plugin_state: nil`.
- Make an instance require plain maps for both fields.
- Validate domain state with the domain schema.
- Validate each Plugin value with the schema for its unique atom key.
- Add the access and replacement functions in T-04.

**Likely code areas**

- `lib/jido/agent.ex`
- `lib/jido/agent/state.ex`
- `lib/jido/agent/validation.ex`
- `lib/jido/plugin.ex`
- `lib/jido/plugin/spec.ex`
- Agent authoring and generated accessors

**Compatibility or migration work**

- Accept `plugin_state` as an instance option.
- Split old combined `state` input with the Plugin keys from normalized specs.
- Reject a Plugin key that appears in old combined input and explicit
  `plugin_state` input.
- Add temporary `Jido.Agent.migrate_combined_state/1` for an old Agent struct or
  map that has no `plugin_state` field. It returns a validated split Agent. Do
  not make normal validation silently accept the old shape forever.
- Until Phase 4, a private Runner adapter can combine the two maps only for the
  old evaluation pipeline. Until Phase 5, the version 1 checkpoint writer can
  combine them only for the old checkpoint format.
- Keep `complete_schema/1` as a documented migration helper.
- Let domain and Plugin maps use the same atom because they are separate
  namespaces.
- Move any domain root refinement that reads Plugin-owned keys to command logic
  or the owning Plugin.

**Verification**

- Add tests for definition and instance shape.
- Add tests for independent defaults and validation.
- Add tests for unique Plugin atom keys, stateless Plugins, unknown Plugin
  keys, missing required Plugin state, and the same atom in both namespaces.
- Prove that domain root refinements receive domain fields only.
- Add old combined-input conversion and collision tests.
- Add access, fetch, replacement, and `set/2` tests.

**Exit criteria**

- Construction produces only the split state shape.
- Every Plugin-owned value is under its declared atom key in `plugin_state`.
- Existing combined constructor input has one deterministic conversion path.

### Phase 4. Switch command evaluation to separate state paths

**Contract changes**

- Give Actions and Flows only domain state in `context.agent_state`.
- Treat executable output as complete domain state only.
- Start Plugin reduction from `agent.plugin_state`.
- Replace only the state value for the current Plugin atom key.
- Assemble and validate both maps as one candidate Agent.

**Likely code areas**

- `lib/jido/agent/command.ex`
- `lib/jido/agent/command/runner.ex`
- `lib/jido/agent/state.ex`
- `lib/jido/plugin.ex`
- `lib/jido/agent_server.ex`

**Compatibility or migration work**

- Remove the need for executable pass-through of Plugin-owned keys.
- Keep Action and Flow return forms unchanged. Their state map now has a
  domain-only meaning.
- Keep `set/2` domain-only.
- Keep Plugin `update_state/3` input as one owned state value.

**Verification**

- Prove that an executable cannot read Plugin state through
  `context.agent_state`.
- Prove that executable output cannot add or replace Plugin state.
- Prove that each Plugin receives and replaces only its declared value.
- Prove declaration order and owned Directive filtering.
- Prove direct and live evaluation produce the same split candidate.

**Exit criteria**

- No command path uses a combined state map after input migration.
- Domain and Plugin validation failures return no candidate.
- The temporary Runner combination adapter is removed.

### Phase 5. Add default checkpoint version 2 and version 1 conversion

**Contract changes**

- Implement T-08 for the default checkpoint path.
- Store `state` and `plugin_state` as separate fields in version 2.
- Require strict normalized static equality at checkpoint creation for a
  versioned module-owned Agent.
- Require the saved module and revision during version 2 restore.

**Likely code areas**

- `lib/jido/agent.ex`
- `lib/jido/persistence.ex`
- Agent checkpoint fixtures and serialization tests

**Compatibility or migration work**

- Continue to read default version 1 checkpoints.
- Split version 1 combined state with Plugin keys from the restored definition.
- Keep direct and behavior-only embedded-definition restore.
- Keep custom callback results, but require callback authors to save both maps
  when the Agent has Plugin state.
- Do not rewrite stored data in place in this phase.

**Verification**

- Add fixtures for version 1 combined maps and version 2 split maps.
- Add direct definition, behavior-only module, and custom callback fixtures.
- Test revision mismatch, module mismatch, static definition mismatch at save,
  malformed versions, and invalid state in either map.
- Enable the skipped definition revision restore test when its expected error
  code is approved.

**Exit criteria**

- New default checkpoints never combine domain state and Plugin state.
- A version 2 module-owned checkpoint cannot restore under another revision.
- Every supported version 1 fixture converts to the split Agent shape.
- Custom checkpoint callbacks still pass their compatibility tests.
- The default writer no longer creates a combined version 1 checkpoint.

### Phase 6. Enforce portable domain state and Plugin state

**Contract changes**

- Implement T-09 with the approved error code and path.
- Run Zoi validation first for each state class. Run portability validation on
  each validated result.

**Likely code areas**

- `lib/jido/portable_term.ex`
- `lib/jido/agent/state.ex`
- `lib/jido/agent/validation.ex`
- `lib/jido/agent/command/runner.ex`
- Plugin state reduction in `lib/jido/plugin.ex`

**Compatibility or migration work**

- Publish the newly rejected state terms.
- Give users a clear conversion rule for PIDs, functions, references, ports,
  improper lists, and non-byte-aligned bitstrings.
- Keep persistence validation as a second check.

**Verification**

- Add table-driven construction and replacement tests for both state maps.
- Add Plugin reduction and direct `cmd/3` tests with exact failing paths.
- Add live Server tests that prove invalid state does not commit.
- Keep and extend the persistence portability tests.

**Exit criteria**

- No direct or live path can make nonportable domain or Plugin state a valid
  Agent candidate.
- Every failure has the approved stable code and exact path.

### Phase 7. Integrate the split with live and persistence owners

**Contract changes**

- Keep one Agent candidate and one Server commit point.
- Commit domain state and Plugin state together.
- Keep `state_version` outside the Agent definition revision.
- Use checkpoint version 2 in new persistent writes.

**Likely code areas**

- `lib/jido/agent_server.ex`
- `lib/jido/agent_server/state.ex`
- `lib/jido/agent_server/runtime_checkpoint.ex`
- `lib/jido/persistence.ex`
- Plugin state integration in `lib/jido/plugin.ex`

**Compatibility or migration work**

- Convert old combined records only through version 1 checkpoint restore.
- Convert a nonpersistent runtime checkpoint or a live old Agent value through
  the same explicit state-split function before the first new Turn.
- Do not add Agent Ref, Commit, or Record structs in this phase.
- Keep current PID-based Agent Server calls until their owner seam approves a
  migration.

**Verification**

- Test direct and live candidate equality for one route.
- Test that domain and Plugin state commit atomically.
- Test that a portability, revision, or restore error causes no live commit.
- Test persistent save, load, hibernate, thaw, and runtime checkpoint restore.
- Update state migration examples to assert both state maps.

**Exit criteria**

- Direct and live evaluation use the same split Agent validation result.
- A commit cannot install only one of the two state maps.
- No internal live or persistence path rebuilds the combined state shape.
- Commit revision, definition revision, checkpoint version, and storage version
  remain distinct.

### Phase 8. Apply an approved route migration, if any

**Contract changes**

- No change if the owner seams retain current behavior.
- If B-01 resolves in favor of the proposal, select one route from the source
  Signal before Plugin preparation and keep that executable fixed.

**Likely code areas**

- `lib/jido/agent/command/runner.ex`
- `lib/jido/agent.ex`
- live Plugin admission and preparation in `lib/jido/agent_server.ex`
- route and Turn tests

**Compatibility or migration work**

- Give users one explicit release note for multiple matches and prepared-Signal
  rewrites.
- Keep custom `handle_signal/2` or define and test its approved replacement
  before deprecation.

**Verification**

- Run all current route tests.
- Enable the two skipped route-selection research tests only if the new rule is
  approved.
- Prove direct and live equality for exact, wildcard, predicate, fallback, and
  prepared-Signal cases.

**Exit criteria**

- The overview, Agent, Turn, Plugin, implementation, and tests state one route
  rule.

### Phase 9. Complete public documentation and release checks

**Contract changes**

- No new behavior.
- Publish the final public Agent contract and migration notes.

**Likely code areas**

- Agent module documentation, guides, changelog, and API migration map.
- External package contract fixtures when the package seam provides them.

**Compatibility or migration work**

- State the authoring document versions and checkpoint versions that the
  release reads and writes.
- State the combined-input compatibility period and the split-state contract.
- State all retained callbacks and APIs.

**Verification**

- Run format, compile, focused tests, the full package suite, research controls,
  and the compatible V3 package matrix.

**Exit criteria**

- Every target item in the acceptance matrix has passing evidence.
- No pending removal exists without a separate approved migration plan.

## 8. Downstream contracts

After this plan is approved, downstream seams can rely on the following plan
targets. Approval does not mean that unimplemented targets already exist.

### Agent authoring

- Neutral definitions remain supported.
- `use Jido.Agent`, Builder, Codec, and `to_map/1` remain supported.
- All forms use the same canonical validation path.
- Instance construction accepts separate `state` and `plugin_state` maps.
- Old combined constructor input has a documented compatibility conversion.
- Definition revision is additive. Old module source and Codec version 1 input
  remain valid.
- Authoring serialization stays separate from checkpoints.

### Agent identity

- An Agent instance has one nonempty binary `id`.
- The Agent value does not define namespace, partition, runtime location, or
  storage identity.
- The identity seam can build a Ref around the instance ID. It must not require
  removal of neutral definitions or direct command evaluation.

### Turn evaluation

- `cmd/3` remains the direct evaluation entry point.
- The Runner returns one candidate Agent and one ordered Directive list.
- The complete candidate has a domain `state` map and a separate
  `plugin_state` map.
- Actions and Flows receive and return domain state only.
- Custom `handle_signal/2` remains supported.
- The exact route and preparation order remains blocked by B-01.

### Plugins

- Plugin declarations remain ordered `{module, options}` values.
- Plugin modules and Plugin state atom keys are unique within one Agent.
- Each stateful Plugin defines its atom key and schema through `state_spec/1`.
- Each stateful Plugin owns one value under that key in
  `agent.plugin_state`.
- A stateless Plugin has no `plugin_state` entry.
- An executable has no Plugin state in `context.agent_state` or its output.
- Plugin reduction runs before final validation of the complete candidate.
- This seam does not require a public `%Jido.Plugin{}` value.

### Persistence

- `Jido.Agent.checkpoint/2` and `restore/3` remain the Agent recovery boundary.
- Current default version 1 combined checkpoint maps remain readable and
  convert to the split state shape.
- New versioned module checkpoints can use the version 2 map in T-08.
- Version 2 stores `state` and `plugin_state` separately.
- Agent definition revision is separate from Server state revision and storage
  version.
- Public Commit, Record, Ref, and checkpoint struct decisions remain with their
  owner seams.

### Agent Server

- The Server owns one current immutable Agent and a separate state version.
- The Server uses the Agent Runner and validation rules. It does not define a
  different Agent state shape.
- One commit installs domain state and Plugin state together.
- A successful direct command is not a commit. A live success becomes public
  only after the Server commit path succeeds.
- Definition revision is static data. It must not increment on each Turn.
- PID-based public calls remain supported until the Server and instance seams
  approve a migration.

## 9. Acceptance matrix

| Target | Current evidence | New or changed evidence required |
| --- | --- | --- |
| T-01, two valid forms | `test/jido/agent_test.exs` covers definition, instance, half-instance, and explicit validation behavior. | Add a stable public API inventory test only if documentation cannot give the inventory. |
| T-02, normalized static definition | `test/jido/agent/validation_test.exs` covers validation order and current Plugin schema composition. | Add separate domain and Plugin schema validation plus definition revision equality tests. |
| T-03, split state maps | Current schema and Plugin contract tests prove Plugin key ownership in the old combined map. | Add struct shape, independent defaults, separate validation, unique atom key, stateless Plugin, same-name domain and Plugin keys, old-input conversion, and collision tests. |
| T-04, state operations | `test/jido/agent_test.exs` covers current transition, deep-merge `set/2`, immutability, and invalid state. | Add domain and Plugin access, fetch, replacement, compatibility transition, and revision preservation tests. |
| T-05, direct command | Current Agent and Plugin tests cover Actions, Flows, Directives, errors, ownership, options, and source immutability. | Prove domain-only executable context and output, per-Plugin reduction, split candidate assembly, and direct/live equality. |
| T-06, route stability or migration | Current Agent tests require exactly one match. Two route research tests are skipped for the proposed rule. | Keep current tests if current behavior wins. Enable and extend skipped tests only after B-01 resolves for the new rule. |
| T-07, definition revision | The definition revision research test records the missing restore rule. | Add compile, constructor, Builder, Codec, equality, and invalid-revision tests. |
| T-08, checkpoint version 2 | `test/jido/agent_test.exs` covers version 1 maps, callbacks, direct definitions, behavior-only modules, and current module restore. | Add version 1 combined conversion, version 2 split fixtures, strict revision, static mismatch, and custom callback compatibility tests. |
| T-09, portable Agent state | The research persistence portability test covers save and load rejection for some runtime terms. | Add non-research construction, replacement, Plugin reduction, direct command, live commit, checkpoint, restore, bitstring, and exact-path tests for both maps. |
| T-10, approved errors | Current Agent tests cover several error modules. The error gap analysis shows that stable codes are missing. | Add table-driven assertions for every new Agent failure after the error seam approves exact codes. |
| T-11, authoring and runtime separation | Builder, Codec, authoring, and serialization contract tests cover current separation. Agent struct tests list current fields. | Add revision round trips, separate `to_map/1` fields, and an explicit no-runtime-handle Agent schema assertion. |
| Live integration | Agent schema tests prove no commit for an invalid candidate. State migration tests prove one old combined-state commit. | Add atomic split-state commit, no-commit cases for either invalid map, and persistent version 1 conversion and version 2 restore. |

## 10. Open decisions that need user approval

1. **Compatibility period:** Decide how long constructors and `transition/2`
   accept old combined state, how long `complete_schema/1` stays a public
   migration helper, and when `migrate_combined_state/1` can be removed.
2. **State operation names:** Approve the accessor and replacement names in
   T-04. The split state direction and unique Plugin atom key are already set by
   user direction.
3. **Definition revision:** Approve T-07. In particular, approve default revision
   1 for `use Jido.Agent` modules and `nil` for direct or behavior-only
   definitions.
4. **Definition equality:** Approve the `===` rule in T-07 for complete
   normalized static definition values at versioned checkpoint creation.
   Confirm that the author must increase the revision for behavior-only code
   changes.
5. **Checkpoint migration:** Approve the version 2 split map, continued version
   1 combined reads, embedded definitions for direct and behavior-only Agents,
   and continued custom callback support.
6. **Checkpoint public type:** The package and persistence owners must decide
   if a public Checkpoint struct is still needed after the map migration. This
   plan recommends deferral.
7. **Route order:** The overview and Turn owners must approve current
   exactly-one prepared-Signal routing or the proposed first-match source-Signal
   routing. This Agent document does not select that contract.
8. **Portable error contract:** The error owner must approve the exact failing
   path format, stable code, error class, and public fields before Phase 3.
9. **Custom checkpoint guarantees:** The package and persistence owners must
   decide if custom callback maps stay outside the revision guarantee, enter a
   new core envelope, or get a new callback contract for both state maps.
10. **Removal policy:** Approve that no current supported Agent API is removed
    without a separate approved deprecation and migration plan.
