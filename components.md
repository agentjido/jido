# Jido V3 Component Map

Status: Working draft for an architecture Grill.

This document maps the current Jido V3 implementation by module namespace. The
current source and public behavior define the component map. Current Covenant
surfaces provide proof evidence. Planned Covenant realignment is migration
context and does not define a current component.

This is not yet the final architecture contract. Items marked **open** need an
explicit boundary decision.

## Component review checklist

Last checked: 2026-11-10, on `migration/consolidated-v3`.

The review covers four required checks for each component:

- [ ] **Public surface:** Record supported entry points, values, options,
  results, errors, and the architectural boundary.
- [ ] **API contract usage:** Trace the contract through current callers,
  consumers, and tests. Identify unused or inconsistent forms.
- [ ] **Duplication:** Check repeated behavior, overlapping types, unused APIs,
  and abstractions that add code without a useful contract.
- [ ] **Elixir design:** Complete a formal Elixir design review of
  responsibilities, data contracts, dependencies, and applicable OTP behavior.

These four boxes define the review procedure. The tables record progress.
`[x]` means the review step has evidence. `[ ]` means that the step still needs
review, or that the available evidence covers only part of the component.
**Reviewed** means all four steps have evidence. It does not mean that all
findings are closed or that the component is ready for release. A confirmed
component boundary in the inventory below does not complete these checks.

Current count: **18 reviewed** and **20 waiting for the full review**.

- Top-level components: **15 reviewed**, **7 waiting**.
- Sub-components: **3 reviewed**, **13 waiting**.
- Before R7, the local checklist recorded **16 reviewed** and **21 waiting**.
  That evidence and the checkpoint note below are retained.
- The latest completed set is Action and Flow (R7).
- The preceding set is Session, Thread, Instruction, Signal,
  Persistence, and Telemetry, plus Signal Router, Bus, and Dispatch.
- Four defect fixes from this set are included in checkpoint `8525ec43`.
  Tests were not run after these fixes. Review completion does not establish
  that all fixes have test evidence.

Some waiting components have focused test evidence, as noted below.

### Top-level components

| Component and review record | Public surface | API contract usage | Duplication | Elixir design | Review state |
| --- | --- | --- | --- | --- | --- |
| `Jido` | [ ] | [ ] | [ ] | [ ] | Waiting |
| [`Jido.Error`](docs/components/error.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R2) |
| [`Jido.Id`](docs/components/id.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R2) |
| [`Jido.Joi`](docs/components/joi.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R2) |
| [`Jido.Expr`](docs/components/expr.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R2) |
| [`Jido.Trace`](docs/components/trace.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R4) |
| [`Jido.Codec`](docs/components/codec.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R4) |
| [`Jido.Catalog`](docs/components/catalog.md) | [x] | [x] | [x] | [x] | Reviewed (R1, R4) |
| [`Jido.Action`](docs/components/action.md) | [x] | [x] | [x] | [x] | Reviewed (R7) |
| [`Jido.Instruction`](docs/components/instruction.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| [`Jido.Flow`](docs/components/flow.md) | [x] | [x] | [x] | [x] | Reviewed (R7) |
| `Jido.Exec` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Durable` | [ ] | [ ] | [ ] | [ ] | Waiting |
| [`Jido.Signal`](docs/components/signal.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| `Jido.Agent` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Plugin` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AgentServer` | [ ] | [ ] | [ ] | [ ] | Waiting |
| [`Jido.Persistence`](docs/components/persistence.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| [`Jido.Session`](docs/components/session.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| [`Jido.Thread`](docs/components/thread.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| `Jido.AI` | [ ] | [ ] | [ ] | [ ] | Waiting |
| [`Jido.Telemetry`](docs/components/telemetry.md) | [x] | [x] | [x] | [x] | Reviewed (R5) |

### Sub-components

Review each sub-component explicitly. A parent review does not complete its
sub-component checks.

| Sub-component | Public surface | API contract usage | Duplication | Elixir design | Review state |
| --- | --- | --- | --- | --- | --- |
| [`Jido.Signal.Router`](docs/components/signal.md#router) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| [`Jido.Signal.Bus`](docs/components/signal.md#bus) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| [`Jido.Signal.Dispatch`](docs/components/signal.md#dispatch) | [x] | [x] | [x] | [x] | Reviewed (R5) |
| `Jido.Plugin.Audit` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Plugin.Bus` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Plugin.Heartbeat` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Plugin.Scheduler` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.Plugin.SensorManager` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.Adaptive` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.AlgorithmOfThoughts` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.ChainOfDraft` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.ChainOfThought` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.GraphOfThoughts` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.ReAct` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.TreeOfThoughts` | [ ] | [ ] | [ ] | [ ] | Waiting |
| `Jido.AI.Reasoning.TRM` | [ ] | [ ] | [ ] | [ ] | Waiting |

`Jido.Instance` stays within the `Jido` review as an internal namespace.
`Jido.Application` needs a composition-root check with that review. Neither is
an additional public component in this checklist.

### Review evidence and remaining work

- **R1 — Foundational public contracts.** The chat **Review jido core migration
  branch** (`01a1c55c-c9d1-7c90-87b7-9d81ce79be21`), turn
  `01a1c577-f647-70a0-bad9-2c5826100593`, produced the seven linked component
  records. They cover public contracts, boundaries, Reach layers, Covenant
  evidence, and proof gaps. This supports the public-surface column for all
  seven. It does not prove a complete usage, duplication, or formal design
  review for Trace, Codec, or Catalog.
- **R2 — Formal utility design review.** The same chat, turn
  `01a1c57f-bb9c-79a1-9e32-a4f21b4258f9`, reviewed only Error, Id, Joi, and Expr.
  It traced source, callers, tests, and component records. It examined unused
  APIs, duplicate error types, and proposed shared abstractions. Id and Expr
  were retained. The review retained the Joi lifecycle and Splode.
- **R3 — Approved review changes.** The same chat, turn
  `01a1c583-e860-7613-8be6-171f295bdc25`, applied the Error and Joi cuts:
  `CompensationError`, `normalize/1`, the `field:` and `action:` validation
  shortcuts, and five unused Joi delegate groups. Callers, docs, tests, and
  contract records were updated. The chat reported passing compilation,
  3,456 default-suite tests, format, and patch checks. These are historical
  checks from that change, not new test results from this checklist update.
- **R4 — Trace, Codec, and Catalog design review complete.** The chat **Review
  jido core migration branch** (`01a1c55c-c9d1-7c90-87b7-9d81ce79be21`), turn
  `01a1c58a-cc00-7233-8a35-ec55dd5f3db0`, completed the formal Elixir design
  review at `85023dd`, including local changes and component records. It
  checked public contracts, current callers, tests, duplication, and reduction
  candidates. Trace retains its value/context split. Catalog was later narrowed through the confirmed scope in ADR 0004. Codec retains separate Term, Value, and Document
  responsibilities and its dependency direction. The chat reported passing
  compilation with warnings as errors, 266 focused tests, and format checks.
  It did not run the full suite or change files. These are review-run results,
  not tests run by this checklist update.
  - Catalog scope confirmed: passive registered-value resolution; no kinds, Views, revisions, or operation snapshots. See `docs/adr/0004-passive-catalog-reference-resolution.md`.

- **R5 — Six component reviews and three Signal sub-component reviews.**
  Applied the explicitly requested `kata:jido` and `elixir-design-review`
  skills on 2026-11-10. Reviewed HEAD `85023dd344969416cab848cbe368ea5d17c96805`
  with existing local changes on `migration/consolidated-v3`. The linked
  Session, Thread, Instruction, Telemetry, Persistence, and Signal records
  cover the four checks. Signal includes separate Router, Bus, and Dispatch
  coverage. Two read-only reviewers checked the thin values/Instruction and
  Bus/Telemetry paths. The primary reviewer checked composition and
  reproduced retained defects. Other paths are self-checked.
  - Focused tests: 184 passed for Session, Thread, Instruction, Telemetry,
    and AI observability; 675 passed with three excluded for Persistence,
    durable AgentServer, Signal, and Signal codec; 14 conversation tests
    passed. These are separate command totals, not a unique coverage count.
  - Temporary probes confirmed Session time regression, unchecked Entry
    encode, retained Exec process state, AI formatter differences,
    unsupported structured AI log output, and tool context retained after
    expiry from another process. Mixed-key and ignored-stats probes support
    open contract decisions. No source fixes were made.
  - `mix compile --warnings-as-errors` and `mix format --check-formatted`
    passed. Local document links and checklist counts passed inspection.
  - `mix test.ci` failed in its first default-test stage: 3,388 of 3,391
    passed, with 372 excluded. Three `InlineHostBuildTest` cases failed
    because temporary build files/directories were missing. The later CI
    stages did not run. This does not establish the cause of the fixture
    failures. No full CI pass is claimed.
  - External store services, live model calls, and a real telemetry collector
    were not tested. Proof ownership and public API decisions remain open.

- **R6 — Defect fixes included in the checkpoint.** In **Review thin Jido
  components** (`01a1c5b7-fa3f-7952-aa6f-f8a52ff50325`), turn
  `01a1c5d1-cd1b-7892-8fa2-43177cce00b6`, the user requested fixes without tests.
  The Session timestamp fix (Session F3), Entry encode validation (Thread F3),
  AI span context cleanup (Telemetry F4), and AI log value filtering
  (Telemetry F5) are included in checkpoint `8525ec43`. That chat reported
  passing compilation, formatting, and diff checks. No tests were added or
  run for the fixes. The checkpoint was committed without completing the
  additional test run, as requested. The earlier R5 tests apply to the review
  state before the fixes. Other findings and design decisions remain open.

- **R7 — Action and Flow reviews.** Applied the explicitly requested
  `kata:jido` and `elixir-design-review` skills on 2026-11-10. Reviewed HEAD
  `8525ec43f71656d8c9c9e5a428388aa87d159ac8` on
  `migration/consolidated-v3`, with the existing local checklist update.
  The Action and Flow records cover all four required checks. They retain
  each namespace as one component, with no added sub-components.
  - One read-only reviewer traced Action. A second traced Flow authoring.
    The primary reviewer traced Flow values, graph rules, preparation,
    defaults, identity, codecs, and cross-component consumers. It checked
    the reduction claims and reproduced the defects.
  - Action has no confirmed defect. One P3 refinement can remove duplicate
    private reservation state. The `raw`/`opaque` overlap remains an API
    decision; no public deletion was approved.
  - Flow has four confirmed defects: module aliases in literals change
    value, duplicate literal module keys can lose an entry, improper array
    defaults can raise, and Selection child diagnostics lose their source
    line. One P3 refinement can remove an identity traversal used by
    inspection. These are open findings, not verified fixes.
  - The focused command passed 587 tests, including Action, Flow, Flow codec,
    Exec/Agent integration, and isolated consumer builds. The authoring
    command passed 8 tests. These are separate command totals.
  - Compilation with warnings as errors and format checks passed. The first
    test attempt failed on Mix's local TCP lock (`:eperm`); the permitted
    retry passed. Full CI, the quality gate, full Covenant checks, and live
    calls were not run. Proof metadata and external compatibility limits
    remain in the records.
  - A separate read-only verifier checked both records against source and
    contract evidence. It found no material record error. All 75 local links,
    checklist counts, and patch checks passed.
  - Only local documentation changed. No production fixes, commits, pushes,
    or publications were made. Review completion does not adopt a finding.

- **R8 — Flow repairs after the review.** The user requested fixes for the Flow
  findings. F1 through F5 are applied locally: declaration-scope aliases,
  canonical literal map-key checks, improper-default error handling, Selection
  child locations, and removal of the internal inspection traversal. The
  Action source is unchanged. Flow obligations I7/I8 were clarified and I12
  now covers the partial-default boundary. The full offline test command
  completed all stages before the final extension and nested-union guards.
  The focused command passed 593 tests; public authoring passed 8 tests.
  All 24 regression tests passed after the nested-union repair.
  The static quality gate stopped at unused Action/Catalog Dialyzer filters.
  ExDNA passed at 17 clones. Reach passed, with 281 advisory findings. A later
  full Covenant run had one durable-turn recovery timeout; that test passed
  alone, and the full retry passed 3,397 tests and 325 obligations. The final
  Covenant check after the nested-union repair passed 3,397 tests and all 325
  obligations. Final format, patch, and 77 local file/section links passed. The
  [Flow record](docs/components/flow.md#r8--local-flow-repairs) holds the proof
  and limits. Review counts before `Jido.Durable` was added were 18 reviewed
  and 19 waiting.

### Remaining review list

The following top-level components still need the full four-step review:

- [ ] `Jido`, including internal Instance services and Application composition.
- [ ] `Jido.Exec`
- [ ] `Jido.Durable`
- [ ] `Jido.Agent`
- [ ] `Jido.Plugin`
- [ ] `Jido.AgentServer`
- [ ] `Jido.AI`

The five bundled Plugin sub-components and eight AI reasoning sub-components
also remain waiting, as listed in the sub-component table above. Do not mark
these complete from a parent review alone.

The seven foundational component reviews are complete. Catalog F1 is superseded by the confirmed scope in ADR 0004. Codec
F2 remains an open recommendation. Their ownership and proof gaps remain visible
in the linked records. The six R5 records and three Signal sub-component reviews are also complete.
The Action and Flow records are complete under R7.
Continue the component review with the waiting rows.
Record later review findings and decisions in each owning component file,
then update the matching checklist row with its evidence.

## Working component rule

A component is one cohesive public capability. It owns a stable behavior
contract and can have several internal modules and Covenant proof surfaces.

A sub-component is an independently usable subsystem inside a component. A
sub-component must meet all these tests:

1. It has a clear public entry point and vocabulary.
2. It provides useful behavior without requiring the parent component's
   primary object or lifecycle.
3. It owns distinct inputs, outputs, state, or invariants.
4. A user can adopt, replace, or reason about it as one capability.
5. Its boundary is useful in the product architecture, not only in code or
   test organization.

A proof surface is a behavior slice that needs direct Covenant evidence but
does not have an independent product identity. A helper or internal part
supports implementation without owning a public capability.

Namespace depth, module count, and Covenant file count are evidence. They do
not define a component or sub-component. Lower-layer dependencies do not become
owned modules of a higher-layer component.

This rule is confirmed. It includes utility components such as Codec and Joi
when they own stable behavior and an independent proof surface.

## Consolidated component inventory

This table classifies the complete current top-level `Jido.*` namespace
surface. **Confirmed** means Mike settled the boundary in this Grill.
**Proposed** means the classification follows the confirmed component test but
still needs review.

| Module namespace | Classification | Sub-components | Important proof surfaces or internal parts | Status |
| --- | --- | --- | --- | --- |
| `Jido` | Component | None | Instance definition, supervision, namespace ownership, Agent start, activation, lookup, listing, stopping, and persistence defaults | Confirmed |
| `Jido.Application` | Application composition, not a public component | None | Shared supervisor and runtime child startup | Proposed |
| `Jido.Error` | Component | None | Error construction, normalization, transport | Proposed |
| `Jido.Id` | Component | None | Identifier creation and validation | Proposed |
| `Jido.Joi` | Component | None | Schema model, static validation, runtime validation | Proposed |
| `Jido.Expr` | Component | None | Parser, operations, limits, runtime evaluation | Proposed |
| `Jido.Trace` | Component | None | W3C Trace values, causation, process-local context, Signal propagation, OpenTelemetry context bridge | Confirmed |
| `Jido.Codec` | Component | None | Compiler, documents, encoder, index, references, portable terms, values, errors, issues | Confirmed |
| `Jido.Catalog` | Component | None | Entry, manifest, discovery, publication | Confirmed |
| `Jido.Action` | Component | None | Inline authoring, validation, output, effect requests | Confirmed |
| `Jido.Instruction` | Component | None | Target values, compiler, configuration | Proposed |
| `Jido.Flow` | Component | None | Graph, components, DSL, inline authoring, validation, values, preparation, codecs | Confirmed |
| `Jido.Exec` | Component | None | Compiler, runtime, frames, nodes, waits, handoffs, Runic integration | Confirmed |
| `Jido.Durable` | Component | None | Persisted Flow execution, portable references and status, Signal wait input, continuation recovery, host scheduling boundary | Proposed |
| `Jido.Signal` | Parent component | `Jido.Signal.Router`, `Jido.Signal.Bus`, `Jido.Signal.Dispatch` | Envelope, context, boundary rules, codec, catalog | Confirmed |
| `Jido.Agent` | Component | None | Route, Turn, Directive, mutation, topology, schema, codec, Plugin preparation, references, views | Confirmed |
| `Jido.Plugin` | Parent component | `Jido.Plugin.Audit`, `Jido.Plugin.Bus`, `Jido.Plugin.Heartbeat`, `Jido.Plugin.Scheduler`, `Jido.Plugin.SensorManager` | Plugin behavior, config, specification, manifest, normalization, contexts, runtime callbacks | Proposed |
| `Jido.AgentServer` | Component | None | Lifecycle, activation, composition, durable Turns, effects, handoff, Plugin runtime, status, topology, supervision | Proposed |
| `Jido.Instance` | Internal namespace of `Jido` | None | Names, namespace registry, options, runtime store | Confirmed internal ownership |
| `Jido.Persistence` | Component | None | Records, snapshots, checkpoints, stores, continuation storage, Plugin conversion, adapters | Proposed |
| `Jido.Session` | Component | None | Session identity, revision, lifecycle, Thread reference | Proposed |
| `Jido.Thread` | Component | None | Append-only entries and interaction history | Proposed |
| `Jido.AI` | Parent component | `Jido.AI.Reasoning.Adaptive`, `Jido.AI.Reasoning.AlgorithmOfThoughts`, `Jido.AI.Reasoning.ChainOfDraft`, `Jido.AI.Reasoning.ChainOfThought`, `Jido.AI.Reasoning.GraphOfThoughts`, `Jido.AI.Reasoning.ReAct`, `Jido.AI.Reasoning.TreeOfThoughts`, `Jido.AI.Reasoning.TRM` | AI Agent authoring, inference client, shared reasoning actions, tools, skills, policy, budget, usage, context, AI Turn behavior | Parent and reasoning sub-components confirmed |
| `Jido.Telemetry` | Component | None | AgentServer, Exec, Persistence, Signal, AI, semantic logging, metrics, OpenTelemetry mapping | Proposed |

### Inventory totals

- 22 proposed or confirmed top-level components. `Jido` replaces the former
  `Jido.Instance` component candidate.
- 16 proposed or confirmed sub-components.
- `Jido.Application` is listed as application composition, not as a public
  component.
- Proof surfaces remain separate from component identity.

## Encoded component tree

Legend:

- **Component**: one cohesive public capability.
- **Sub-component**: an independently usable subsystem under a component.
- **Proof surface**: a contract slice that needs direct evidence but has no
  independent component identity.
- **Candidate**: not yet confirmed in this Grill.

```text
Jido package
├── Jido                                     component, confirmed
│   └── Jido.Instance                        internal namespace and proof surface
├── Jido.Application                         composition root, not a component
├── Jido.Error                               component, candidate
├── Jido.Id                                  component, candidate
├── Jido.Joi                                 component, candidate
├── Jido.Expr                                component, candidate
├── Jido.Trace                               component, confirmed
│   ├── Trace value                          proof surface
│   └── Trace context                        proof surface
├── Jido.Codec                               component, confirmed
├── Jido.Catalog                             component, candidate
├── Jido.Action                              component, confirmed
├── Jido.Instruction                         component, candidate
├── Jido.Flow                                component, confirmed
├── Jido.Exec                                component, confirmed
├── Jido.Durable                             component, candidate
├── Jido.Signal                              parent component, confirmed
│   ├── Jido.Signal.Router                   sub-component, confirmed
│   ├── Jido.Signal.Bus                      sub-component, confirmed
│   └── Jido.Signal.Dispatch                 sub-component, confirmed
├── Jido.Agent                               component, confirmed
├── Jido.Plugin                              parent component, candidate
│   ├── Jido.Plugin.Audit                    sub-component, candidate
│   ├── Jido.Plugin.Bus                      sub-component, candidate
│   ├── Jido.Plugin.Heartbeat                sub-component, candidate
│   ├── Jido.Plugin.Scheduler                sub-component, candidate
│   └── Jido.Plugin.SensorManager            sub-component, candidate
├── Jido.AgentServer                         component, candidate
├── Jido.Persistence                         component, candidate
├── Jido.Session                             component, candidate
├── Jido.Thread                              component, candidate
├── Jido.AI                                  parent component, confirmed
│   ├── Jido.AI.Reasoning.Adaptive           sub-component, confirmed
│   ├── Jido.AI.Reasoning.AlgorithmOfThoughts sub-component, confirmed
│   ├── Jido.AI.Reasoning.ChainOfDraft       sub-component, confirmed
│   ├── Jido.AI.Reasoning.ChainOfThought     sub-component, confirmed
│   ├── Jido.AI.Reasoning.GraphOfThoughts    sub-component, confirmed
│   ├── Jido.AI.Reasoning.ReAct              sub-component, confirmed
│   ├── Jido.AI.Reasoning.TreeOfThoughts     sub-component, confirmed
│   └── Jido.AI.Reasoning.TRM                sub-component, confirmed
└── Jido.Telemetry                           component, candidate
```

The detailed namespace sections below map these components to current Covenant
surfaces, proof partitions, internal modules, and open migration work.

## `Jido.Error`, `Jido.Id`, `Jido.Joi`, `Jido.Expr`, and `Jido.Trace`

These namespaces provide small foundation behaviors.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Error | Stable error values and normalization | `jido.error` | `jido.error` | Mostly clear |
| ID | Stable identifier creation and validation | No focused component | `jido.id` | Proof gap |
| Joi | Schema definition and validation | Part of broad authoring surfaces | `jido.joi` | Ownership split needed |
| Expression | Portable expression parsing and evaluation | `jido_action.expression` | `jido.expr` | Rename needed |
| Trace | Portable trace and context values | Part of `jido.telemetry` | `jido.trace` | Split from live telemetry |

Open boundary: Decide whether these are five peer components or whether ID and
Joi are internal primitives with proof attached to their consumers.

## `Jido.Codec`

Codec owns boundary representation. The current namespace mixes compile-time
generation, versioned documents, domain codecs, references, portable term
encoding, and runtime document routing.

| Component | Major function | Current Covenant surface | Migration note | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Codec` | Compile codecs, route documents, encode portable terms, validate values and references, and report codec issues | `jido_action.codec` and parts of `jido_action.authoring` | Current Covenant ownership does not match the consolidated namespace | Component confirmed |

Resolved boundary: Codec is one component. Compiler, Term, Value, Reference,
Index, Document, Error, and Issue are internal parts or proof surfaces. They are
not Codec sub-components.

## `Jido.Catalog`

Catalog is the immutable application-wide inventory of trusted definitions.
Discovery builds and atomically publishes the Catalog and Codec index.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Catalog value | Registered identity, version, provider, and target lookup | Part of `jido_action.authoring` | `jido.catalog` | Focused owner needed |
| Catalog discovery | Scan installed applications and publish one inventory | No focused component | `jido.catalog.discovery` | Composition boundary proposed |

Open boundary: Decide whether discovery owns Codec index publication or only
definition discovery.

## `Jido.Action`

Action defines one validated unit of work. It does not own workflow structure,
Agent state commit, or effect dispatch.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Action` | Action contract, callback, inline authoring, output normalization, and validation | `jido_action.action`, `jido_action.inline`, `jido_action.output`, `jido_action.validation` | One `jido.action` component with focused proof surfaces | Component confirmed; proof IDs need realignment |

Resolved boundary: Output, validation, and inline authoring are focused proof
surfaces inside the `Jido.Action` component. They are not separate
architectural components.

## `Jido.Instruction`

Instruction is the portable invocation value for an Action or Flow target.
Its compiler and configuration helpers turn authored declarations into that
value.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Instruction | Target, parameters, context, and execution policy | `jido_action.instruction` | `jido.instruction` | Rename needed |

Open boundary: Decide whether compilation is part of Instruction or a shared
authoring component.

## `Jido.Flow`

Flow is the Agent behavior and composition boundary. It contains graph
structure, components, references, values, and authoring forms. It does not own
live process lifecycle or Agent commit.

| Component | Major function | Current Covenant surface | Migration note | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Flow` | Portable graph, components, values, identity, validation, DSL, inline authoring, codecs, and preparation | `jido_action.flow`, `jido_action.inline_flow`, and parts of `jido_action.codec` | Current proof IDs retain old package names | Component confirmed |

Resolved boundary: Flow is one component. Its DSL, graph, validation, inline
authoring, codec, and preparation paths are internal parts or proof surfaces.

## `Jido.Exec`

Exec binds, compiles, and runs Actions and Flows. It owns typed waits,
handoffs, execution facts, and task cleanup. It does not own persistence,
Agent commit, or Plugin lifecycle.

| Component | Major function | Current Covenant surface | Migration note | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Exec` | Compile and execute Actions and Flows, including waits, handoffs, nodes, frames, and runtime cleanup | `jido_action.execution` and `jido_action.boundary` | Current proof IDs retain the old package name | Component confirmed |

Resolved boundary: Exec is one component. Action-boundary, wait, node, runner,
and Runic behavior are internal parts or proof surfaces.

## `Jido.Durable`

Durable runs persisted Flows from Signals without an Agent. It owns portable
execution references and status, saved continuation data, wait input receipts,
and the host scheduling boundary. It reuses Exec, Runic history, and
Persistence Store adapters. It does not own a scheduler, queue, public Journal,
or Agent state commit.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Durable` | Start, resume, inspect, and signal one persisted Flow | Covered by unit tests and durable AgentServer surfaces | Focused public durable execution surface | Proposed component; public-shape review open |

## `Jido.Signal`

Signal owns the portable event envelope and pure routing data. Its namespace
also contains local bus and external dispatch behavior.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Signal` | Envelope, context, boundary rules, and wire codec | No focused component | `jido.signal` | Parent component confirmed |
| `Jido.Signal.Router` | Routes, selectors, precedence, and router DSL | No focused component | Focused proof under `jido.signal` or a dedicated sub-component ID | Sub-component confirmed |
| `Jido.Signal.Bus` | Local Bus, subscriptions, stores, acknowledgement, and delivery state | Mostly covered through Plugin Bus | Focused proof under `jido.signal` or a dedicated sub-component ID | Sub-component confirmed |
| `Jido.Signal.Dispatch` | Dispatch adapters and external delivery boundaries | No focused component | Dedicated sub-component with focused proof surfaces | Sub-component confirmed |

Resolved boundary: `Jido.Signal.Router` and `Jido.Signal.Bus` are sub-components
of `Jido.Signal`. They are not only proof partitions.

Resolved boundary: `Jido.Signal.Dispatch` is a sub-component. Signal core,
Router, Bus, and Dispatch are four distinct functional owners under the parent
Signal component.

## `Jido.Agent`

Agent owns definitions, immutable state, routes, topology data, candidate
transitions, mutations, and directives. It does not own the live process or
durable commit lifecycle.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido.Agent` | Definitions, schemas, routes, Turns, Directives, Plugins, state, mutation, views, references, and topology data | `jido.agent`, `jido.agent_evaluation`, and part of `jido.instance` | Planned proof realignment is secondary | Component confirmed |

Resolved boundary: Agent is one component. Route, Turn, Directive, mutation,
topology, codec, schema, Plugin preparation, references, and views are internal
parts or proof surfaces.

## `Jido.Plugin`

Plugin is the capability extension contract. It separates Agent authoring,
owned state, route preparation, pure reduction, runtime admission, supervised
children, post-commit work, dispatch, and persistence conversion.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Plugin contract | Callback facets and Agent-owned Plugin behavior | `jido.plugin` | `jido.plugin` | Cross-layer split needed |
| Plugin definition | Config, manifest, specification, and normalization | Part of `jido.plugin` | `jido.plugin.definition` | New focused owner proposed |

Open boundary: Decide if Plugin is one cross-layer extension protocol or a
definition component plus a runtime protocol.

## `Jido.Plugin.*` included capabilities

These are first-party capabilities built on the Plugin contract.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Audit | Keep bounded committed audit records | `jido.plugin.audit` | `jido.plugin.audit` | Clear |
| Bus Manager and Client | Own a Bus and consume Signal subscriptions | `jido.plugin.bus` | `jido.plugin.bus` | Relationship to Signal delivery is open |
| Heartbeat | Send periodic Agent input | `jido.plugin.heartbeat` | `jido.plugin.heartbeat` | Clear |
| Scheduler | Deliver delayed and recurring Signals | `jido.plugin.scheduler` | `jido.plugin.scheduler` | Clear |
| Sensor Manager | Reconcile supervised input sensors | `jido.plugin.sensor_manager` | `jido.plugin.sensor_manager` | Clear |

Open boundary: Decide whether each included capability is part of core Jido or
only shipped in the same package for convenience.

## `Jido.AgentServer`

AgentServer is the live OTP owner. It serializes Turns, validates and commits
candidate state, manages continuations and recovery, and executes post-commit
work.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| AgentServer lifecycle | Start, stop, admit, serialize, commit, and report status | `jido.agent_server` | `jido.agent_server` | Broad runtime owner |
| Activation | Restore or create a durable Agent activation | `jido.agent_server.activation` | Focused AgentServer surface | Retain, exact ID open |
| Composition | Reconcile live parent, child, and connection topology | `jido.agent_server.composition` | Focused AgentServer surface | Retain, exact ID open |
| Durable execution | Host durable Flow execution and recovery through `Jido.Durable.Runtime` | `jido.agent_server.durable` | Focused AgentServer host surface | Generic execution belongs to Durable |
| Durable Turn | Record and settle one durable Turn | `jido.agent_server.durable_turn` | Focused AgentServer surface | Overlaps lifecycle |
| Effects | Run post-commit effects and replies | `jido.agent_server.effects` | Focused AgentServer surface | Agent Directive ownership must move out |
| Handoff | Transfer execution or control to another target | `jido.agent_server.handoff` | Focused AgentServer surface | Relationship to Exec handoff is open |
| Plugin runtime | Start, stop, quiesce, and reconcile Plugin runtime children | `jido.agent_server.plugin_runtime` | Focused AgentServer surface | Retain |

Open boundary: AgentServer has the largest set of focused Covenant surfaces.
Decide which are real architectural components and which are proof partitions
inside one runtime component.

## `Jido` and `Jido.Instance`

`Jido` is the public instance supervisor and Agent-management facade. It defines
Jido instances, owns their supervision trees and namespaces, and provides the
public functions to start, activate, find, list, and stop Agents.

`Jido.Instance` is an internal support namespace. It provides names, namespace
registration, validated options, and runtime storage for the public `Jido`
component. There is no `Jido.Instance` facade module in the current source.

| Component | Major function | Current Covenant surface | Migration note | Boundary status |
| --- | --- | --- | --- | --- |
| `Jido` | Define and supervise Jido instances and manage live or durable Agents | `jido.instance` and AgentServer integration surfaces | Current Covenant naming describes the internal namespace instead of the public facade | Component confirmed |

Resolved boundary: `Jido` is the component. `Jido.Instance` is an internal
namespace and proof surface of `Jido`, not a separate component.

## `Jido.Persistence`

Persistence owns durable records, snapshots, checkpoints, byte stores,
adapters, compare-and-swap rules, and recovery contracts. It does not own live
Agent process state.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Persistence | Record, snapshot, checkpoint, store, adapter, and recovery behavior | `jido.persistence` | `jido.persistence` | Clear owner, broad surface |
| Continuation store | Durable storage bridge for Runic execution | Covered through persistence and durable runtime | Open | Boundary needs evidence |
| Persistence Plugin facet | Convert Plugin-owned state during checkpoint work | Covered through Plugin and persistence | Open | Cross-component protocol |

Open boundary: Decide if adapters are one component contract or if the store
contract and Agent checkpoint contract need separate proof owners.

## `Jido.Session` and `Jido.Thread`

Session and Thread are portable interaction values. They are useful to AI, but
AI does not own them.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Conversation values | Session identity, revision, lifecycle, Thread, and append-only entries | Part of `jido_ai.conversation` | `jido.conversation` | Split from AI needed |
| AI conversation projection | Convert Session and Thread state to model messages | `jido_ai.conversation` | `jido.ai.conversation` | Focused AI owner needed |

Open boundary: Decide if Session and Thread form one Conversation component or
two independent value components.

## `Jido.AI`

AI is a first-party Plugin capability. It contributes Agent authoring, one
request route, reasoning Flows, tools, model-call context, budgets, usage, and
AI telemetry. Model calls and tool execution use normal Actions and Flows.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| AI Agent authoring | Define a normal Agent with the AI Plugin | `jido_ai.agent_authoring` | `jido.ai.agent_authoring` | Rename needed |
| AI conversation | Project portable interaction state to model messages | `jido_ai.conversation` | `jido.ai.conversation` | Must lose value ownership |
| Model execution | Call the inference boundary with policy, budget, and usage | `jido_ai.model_execution` | `jido.ai.model_execution` | Rename needed |
| AI observability | Correlate model and tool execution telemetry | `jido_ai.observability` | `jido.ai.observability` | Rename needed |
| Adaptive | Adaptive reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| Algorithm of Thoughts | Algorithm-of-Thoughts reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| Chain of Draft | Chain-of-Draft reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| Chain of Thought | Chain-of-Thought reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| Graph of Thoughts | Graph-of-Thoughts reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| ReAct | Iterative model and tool reasoning Flow | `jido_ai.react` | Dedicated sub-component proof surface | Sub-component confirmed |
| Tree of Thoughts | Tree-of-Thoughts reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| TRM | TRM reasoning Flow | `jido_ai.strategies` | Dedicated sub-component proof surface | Sub-component confirmed |
| Tools | Tool schema, source, policy, and results | `jido_ai.tools` | `jido.ai.tools` | Rename needed |
| AI Turn | AI request and result behavior inside an Agent Turn | `jido_ai.turn` | `jido.ai.turn` | Relationship to Agent Turn is open |

Resolved boundary: Each current reasoning approach is a sub-component of
`Jido.AI`. Shared reasoning actions and result values remain internal parts of
the AI parent component.

Open boundary: Decide whether tools, model execution, and AI Agent authoring
are additional AI sub-components or proof surfaces of the parent.

## `Jido.Telemetry`

Telemetry observes AgentServer, Exec, Persistence, Signal, and AI behavior. It
must not decide state, routing, recovery, or retry policy.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Runtime telemetry | Stable semantic events, metrics, logging, and OpenTelemetry mapping | `jido.telemetry` | `jido.telemetry` | Trace values must move out |

Open boundary: Decide whether subsystem telemetry modules belong to their
observed subsystem or to one central telemetry component.

## `Jido.Application`

The OTP application composes shared runtime services. It starts the Signal
registry, Exec task supervisor, Catalog discovery, AI correlation store,
Instance namespace registry, persistence owner, and Runic runner.

| Component | Major function | Current Covenant surface | Target Covenant surface | Boundary status |
| --- | --- | --- | --- | --- |
| Application composition | Start and supervise the shared Jido runtime | No focused component | `jido.application` | Stable gap |

Open boundary: Decide whether application startup is a major component or only
an integration contract over the runtime components that it starts.

## Decision ledger

### D1. Component identity rule

Status: Resolved by Mike.

Decision: A component is a stable behavior owner with an independent
contract and proof surface. Namespace shape and current Covenant file count are
evidence, but neither one defines component identity by itself.

Utility behavior is not excluded. Codec, Joi, and similar utilities are
components when they meet this rule.

### D2. Covenant granularity

Status: Resolved by Mike.

Decision: An architectural component can have more than one Covenant
proof surface. A focused Covenant record becomes a separate component only
when it has its own stable behavior, ownership boundary, and change reason.
The existence of a Covenant record alone does not create a component.

Example: `Jido.Action` is one component. Action validation, output, inline
authoring, and the main Action contract can have separate Covenant proof
surfaces.

### D3. Namespace and runtime boundaries

Status: Resolved by Mike.

Question case: `Jido.Signal` contains portable Signal values and routing rules,
but it also contains live Bus and dispatch behavior.

Decision: Components can contain sub-components that own distinct major
functionality. `Jido.Signal` is the parent component. `Jido.Signal.Bus` and
`Jido.Signal.Router` are definite sub-components. Each can have several
Covenant proof surfaces.

This creates three levels in the map:

1. Parent component.
2. Functional sub-component.
3. Covenant proof surface.

### D4. Signal dispatch ownership

Status: Resolved by Mike.

Question case: `Jido.Signal.Dispatch` contains adapter contracts and concrete
delivery adapters for Bus, HTTP, logger, PID, and PubSub targets.

Decision: `Jido.Signal.Dispatch` is a third Signal sub-component. Dispatch has
its own public adapter boundary and can change without changing Signal values,
Router matching, or Bus subscription state.

### D5. Map time horizon

Status: Resolved by Mike.

Decision: The main list describes the current implementation. Planned target
boundaries and Covenant changes are secondary migration notes.

### D6. Codec sub-components

Status: Resolved by Mike.

Current source has one public document router in `Jido.Codec`, compile-time
generation in `Jido.Codec.Compiler`, portable BEAM term encoding in
`Jido.Codec.Term`, and smaller value, reference, index, and issue helpers.

Decision: Codec is one component. Compiler, Term, Value, Reference, Index,
Document, Error, and Issue are internal parts or proof surfaces. They are not
sub-components.

### D7. Flow sub-components

Status: Resolved by Mike.

Current source puts the graph model, components, values, validation, DSL,
inline authoring, codecs, and preparation under `Jido.Flow`.

Decision: Flow is one component. Its DSL, inline authoring, graph, validation,
codec, and preparation paths are proof surfaces or internal parts. They
implement one coherent Flow definition and composition contract.

### D8. Exec sub-components

Status: Resolved by Mike.

Current source puts compilation, runtime execution, waits, facts, frames, node
execution, and Runic integration under `Jido.Exec`. Portable durable
continuations belong to `Jido.Durable`.

Decision: Exec is one component. These areas implement one execution contract.
Action-boundary, wait, node, runner, and Runic behavior are proof surfaces or
internal parts.

### D9. Agent sub-components

Status: Resolved by Mike.

Current source puts the Agent definition and state together with Route, Turn,
Directive, mutation, topology, Plugin preparation, codec, and view behavior
under `Jido.Agent`.

Decision: Agent is one component. Route, Turn, Directive, mutation, topology,
codec, schema, Plugin preparation, references, and views are internal parts or
proof surfaces. They do not provide an independently adoptable capability
outside the Agent contract.

### D10. Component classification test

Status: Resolved by Mike.

Decision: A sub-component is not only an important class, phase,
datatype, namespace, or proof partition. It is an independently usable
subsystem that has a public entry point, distinct invariants, and useful
behavior without the parent component's primary object or lifecycle.

Examples under this test:

- `Jido.Signal.Bus`, `Jido.Signal.Router`, and `Jido.Signal.Dispatch` are
  sub-components because applications can use and reason about each subsystem
  as a distinct Signal capability.
- Agent Route and Agent Turn are proof surfaces inside `Jido.Agent` because
  their meaning and lifecycle are part of the Agent contract.
- Codec Compiler and Codec Term are internal parts of `Jido.Codec` because they
  implement the one Codec capability.

### D11. AgentServer sub-components

Status: Open. Owner: Mike.

Current source has focused AgentServer behavior for activation, composition,
durable execution, durable Turns, effects, handoff, Plugin runtime, lifecycle,
status, topology, and supervision.

Recommended direction: Treat `Jido.AgentServer` as one component. These areas
all require the AgentServer lifecycle and primary Agent process. Keep them as
Covenant proof surfaces, not sub-components.

### D12. AI reasoning approaches

Status: Resolved by Mike.

Decision: Each current AI reasoning approach is a sub-component of `Jido.AI`:

- `Jido.AI.Reasoning.Adaptive`
- `Jido.AI.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Reasoning.ChainOfDraft`
- `Jido.AI.Reasoning.ChainOfThought`
- `Jido.AI.Reasoning.GraphOfThoughts`
- `Jido.AI.Reasoning.ReAct`
- `Jido.AI.Reasoning.TreeOfThoughts`
- `Jido.AI.Reasoning.TRM`

Shared reasoning Actions and `Jido.AI.Reasoning.Result` are internal parts of
the AI parent component.

### D13. Trace boundary

Status: Resolved by Mike.

Decision: Treat `Jido.Trace` as one utility component with no
sub-components. It owns a portable W3C Trace value and the context propagation
needed to carry that value through Signals, AgentServer Turns, tasks, effects,
plugins, and OpenTelemetry.

Use two proof surfaces:

1. Trace value: ID validation, W3C traceparent and tracestate, child spans,
   causation, and metadata.
2. Trace context: process-local capture, restoration, Signal propagation, and
   the OpenTelemetry context bridge.

`Jido.Trace.Context` is not a sub-component because it has no useful behavior
without the Trace value and propagation contract. Trace is not part of
`Jido.Telemetry` because runtime behavior uses Trace for causation and Signal
propagation even when no telemetry reporter is active.

### D14. Main Jido facade

Status: Resolved by Mike.

Decision: The main `Jido` module is a component. It is the public instance
supervisor and Agent-management facade. `Jido.Instance` is its internal support
namespace and proof surface, not a separate component.

Likely next decisions:

- Covenant granularity
- Runtime versus value boundaries
- Core versus included capabilities
- AgentServer decomposition
- Codec reduction
- Signal delivery ownership
- Conversation ownership
- AI component granularity
