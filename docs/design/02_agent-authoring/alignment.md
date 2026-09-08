> Seam alignment plan. This document is pending approval.

# Agent authoring alignment

## Status

- Design reviewed: 2026-09-08. This seam is pending approval.
- Code reviewed: `dc2b6844086a90f384102b2459f800a737f0cfdd` on branch
  `v3-spike`.
- Prerequisite alignments: [00 Overview](../00_overview/alignment.md),
  [90 Package boundaries](../90_package-boundaries/alignment.md),
  [12 Errors and contracts](../12_errors-and-contracts/alignment.md), and
  [01 Agent](../01_agent/alignment.md), all used as pending draft
  prerequisites.
- Alignment state: `Draft`.

The alignment state is execution status. It is not document approval. This
document gives outcomes and gates. It is not a formal implementation plan.

## Inputs and evidence

### Design

- [Jido V3 vision](../VISION.md): requires supported authoring forms to produce
  one normalized Agent definition and keeps developer composition explicit.
- [Overview design](../00_overview/design.md): keeps DSL, direct data, Builder,
  Codec, neutral definitions, and authoring extensions during migration.
- [Package-boundary design](../90_package-boundaries/design.md): keeps static
  authoring extensions separate from Plugins and runtime hooks.
- [Errors and contracts design](../12_errors-and-contracts/design.md): supplies
  pending authoring failure and bang-function rules.
- [Agent design](../01_agent/design.md): owns the two Agent forms and the
  pending compatible definition-revision contract.
- [Target design](design.md): defines the recommended authoring target.

### Canonical code

| Evidence path | Canonical current behavior |
| --- | --- |
| `lib/jido/agent.ex:48-84,137-247` | `use Jido.Agent` installs Spark, inline Actions, module accessors, constructors, direct `cmd/3`, and persistence callbacks. |
| `lib/jido/agent.ex:182-188,259-307` | `agent/0` uses the canonical constructor. Direct definitions and module instances have separate public entries. |
| `lib/jido/agent/validation.ex:10-22,35-39,137-205` | One definition key set and constructor normalize static data, compose Plugins, normalize routes, and limit instance overrides. No revision field exists. |
| `lib/jido/agent/authoring.ex:28-79,107-110` | Route forms use `defaults`. Explicit defaults require a plain map. The legacy target tuple accepts any map, including a struct. |
| `lib/jido/agent/dsl/compiler.ex:7-71,104-108` | The compiler combines forms, lowers extensions, records private interface metadata, generates functions, and verifies the canonical definition after compile. |
| `lib/jido/agent/dsl/compiler.ex:145-278` | Interface compilation checks exact routes, uniqueness, Signal source, argument order, schema fields, and function conflicts. |
| `lib/jido/agent/dsl/macros.ex:27-71,104-135` | A route has one named or extension target, or one inline Action. Inline syntax compiles through `Jido.Action.Inline`. |
| `lib/jido/agent/dsl/generator.ex:4-29,81-159` | Generated helpers have docs and types for tagged Signal, bang Signal, and live-call roles. |
| `lib/jido/agent/interface.ex:8-71` | Runtime packaging separates payload, Signal envelope, caller context, and timeout options. |
| `lib/jido/agent/builder.ex:34-65,80-126` | Builder keeps its first error, appends ordered values, validates targets, and finishes through Agent construction. It has no revision or extension field. |
| `lib/jido/agent/codec.ex:27-99` | Codec version 1 stores static definition fields. Encoding first validates the complete supplied Agent. Decode uses the canonical constructor. |
| `lib/jido/agent/codec.ex:103-147` | Route records store `defaults` and Registry identifiers. Codec keeps the legacy struct-default tuple form on decode. |
| `lib/jido/agent/codec/data.ex:6-59,61-170` | Closed tagged data rejects runtime values and checks depth, node, collection, and string limits. |
| `lib/jido/agent/codec/registry.ex:27-72,75-145` | Registry validates typed entries, unique values, and direct aliases. Route predicates must be external unary captures. |
| `lib/jido/plugin/codec.ex:1-46` | Plugin Codec stores canonical module and options through the same Registry and excludes Plugin state and runtime. |
| `lib/jido/agent/extension.ex:1-23,57-95` | Extension lowering is pure by contract, ordered, and callable as a function, but the entry is not public documentation. |

### Tests and examples

| Evidence path | Behavior proved or specified |
| --- | --- |
| `test/jido/agent/authoring_test.exs:207-255` | One fixture proves definition parity across map, keyword, module, Spark, Builder, and JSON forms and proves direct/live execution agreement. |
| `test/jido/agent/authoring_test.exs:257-318` | Inline route Actions are ordinary reusable Actions and support guarded callback clauses. |
| `test/jido/agent/authoring_test.exs:320-450` | Generated helpers preserve omitted and explicit values, publish docs and types, reject ambiguous input, and leave executable validation to execution. |
| `test/jido/agent/authoring_test.exs:453-527` | Wildcard and external predicate routes, Plugin Codec, Registry aliases, and current instance-encoding state parsing are covered. |
| `test/jido/agent/authoring_test.exs:529-743` | Codec limits, closed data, direct route forms, compile diagnostics, `params` rejection, and Plugin-label rejection are covered. |
| `test/jido/agent/authoring_test.exs:745-779` | After-verification checks support an Action declared later in the same source file. |
| `test/jido/agent/authoring_contract_test.exs:13-56` | Public boundaries have distinct duplicate policies and preserve the route-default compatibility exception. |
| `test/jido/agent/builder_test.exs:19-80` | Builder target checks, declaration order, reuse, and first-error retention are covered. |
| `test/jido/agent/codec_test.exs:29-76` | Codec round-trips all accepted default forms and stops at the first target error. |
| `test/jido/agent/authoring_extension_test.exs:111-286` | Spark extension order, target claims, unclaimed entities, common validation, and error cases are covered. |
| `test/jido/agent/serialization_contract_test.exs:9-43` | Agent authoring JSON and persistence records use separate namespaces and formats. |
| `test/examples/99_research/99_12_definition_revision/definition_revision_test.exs:16-27` | Current restore passes. Revision mismatch remains a skipped target case. |
| `test/examples/01_basic/README.md:1-18` | The Basic suite has five fixtures and 16 tests. It does not contain five cross-form parity tests. |

### Retained validation record

The superseded gap analysis recorded these results on 2026-09-08:

- Focused authoring, Builder, Codec, Registry, validation, and extension
  suites: 64 tests passed.
- Basic examples with the example tag: 16 tests passed.

This documentation consolidation did not rerun runtime tests. The recorded
results prove current behavior only. A skipped test is not passing evidence.

## Retained baseline

- `AUTH-RB-001`: Module, Spark, direct map and keyword, Builder, and Codec forms
  are supported and end at Agent validation.
- `AUTH-RB-002`: Neutral definitions and instances are separate. Authoring
  Codec data does not store ID or state.
- `AUTH-RB-003`: Spark can declare schema, metadata, ordered Plugins, ordered
  routes, inline Actions, Signal source, and explicit interfaces.
- `AUTH-RB-004`: `agent/0` is the canonical module definition.
  `__agent_config__/0` can contain pre-normalized compiler data.
- `AUTH-RB-005`: Inline Actions compile to normal `jido_action` Action modules.
  `route_action/1` makes the target reusable.
- `AUTH-RB-006`: Generated interfaces package input and delegate. They do not
  perform Plugin preparation or executable validation.
- `AUTH-RB-007`: Builder preserves route order and its first error. It does not
  execute Actions.
- `AUTH-RB-008`: Codec uses a closed JSON-compatible format and trusted typed
  Registry. Stored strings cannot create atoms or modules.
- `AUTH-RB-009`: Direct and Builder routes can use valid runtime predicates.
  Registry accepts only external unary captures for route predicates.
- `AUTH-RB-010`: Explicit route defaults require a plain map. A legacy target
  tuple accepts map structs, and Codec preserves this form.
- `AUTH-RB-011`: Agent extensions lower Spark entities in declaration order to
  ordinary Agent configuration. Builder and Codec have no extension-entity
  input.
- `AUTH-RB-012`: Current definitions, Builder data, and Codec version 1 contain
  no definition revision.
- `AUTH-RB-013`: Custom domain helpers remain ordinary Elixir functions.
  `define` is an explicit request for standard generated route helpers.

## Gap register

All dispositions are recommendations and are pending approval.

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| `AUTH-GAP-001` | `AUTH-REQ-001` to `AUTH-REQ-008` | Agent validation, authoring, and parity tests above | Supported forms converge for the covered fixture. Parity and the defaults exception are not stated as one target contract. | `Retain`; clarify the contract |
| `AUTH-GAP-002` | `AUTH-REQ-009` to `AUTH-REQ-015` | Agent module and compiler evidence above | `agent/0` is canonical, but old text called private compiler config normalized. No revision exists. | `Retain` module authority; `Change, staged` for revision |
| `AUTH-GAP-003` | `AUTH-REQ-016` to `AUTH-REQ-020` | Inline macro and tests above | Inline Action behavior is implemented. Old text names a stale dependency version. | `Retain`; remove the version claim |
| `AUTH-GAP-004` | `AUTH-REQ-021` to `AUTH-REQ-034` | Compiler, generator, interface, and tests above | Generated interfaces work only for modules, but old parity text did not state this boundary. | `Retain`; define module-only API separately |
| `AUTH-GAP-005` | `AUTH-REQ-035` to `AUTH-REQ-039`, `AUTH-REQ-061` | Builder code and tests above | Builder behavior works. Module input starts from private compiler data before final normalization. It does not accept a future revision field. Several public functions have no types. | `Retain`; make canonical module parity explicit, then add revision and complete public types |
| `AUTH-GAP-006` | `AUTH-REQ-040` to `AUTH-REQ-049` | Codec, Registry, Plugin Codec, and tests above | Codec is safe and static, but generated instance encoding can parse state twice. Version 1 has no revision. Valid closures are not encodable. | `Change, compatible` for definition-first encode and revision; clarify portable subset |
| `AUTH-GAP-007` | `AUTH-REQ-050` to `AUTH-REQ-054` | Extension code and tests above | Spark calls lowering. The pure function is hidden from public docs. Builder and Codec cannot carry source entities. | `Change documentation and public entry`; keep lowered-data model |
| `AUTH-GAP-008` | `AUTH-REQ-055` | Compiler and recompilation test above | Later-module verification is implemented. | `Retain` |
| `AUTH-GAP-009` | `AUTH-REQ-056` | Authoring functions return validation errors; public types are uneven | Final stable codes and normalization depend on pending seam 12. | `Defer` exact error shape; align after approval |
| `AUTH-GAP-010` | All requirements | One fixture has cross-form parity | There is no requirement-mapped test set across representative Plugins, Actions, Flows, routes, defaults, metadata, and revision. | `Change evidence` |

## Dispositions of superseded material

| Earlier material or conflict | Disposition | Reason and owner |
| --- | --- | --- |
| Use only versioned Agent modules and remove Builder, Codec, Registry, direct data, and neutral definitions. | `Remove` as a target. | The APIs are public and tested. Pending `OVR-REQ-063`, `PKG-REQ-034`, and `AGT-REQ-022` to `AGT-REQ-024` preserve them. |
| Make every Agent definition module-owned and versioned. | `Change in stages`. | Seam 01 recommends revisions for generated modules and permits unversioned direct and behavior-only definitions. |
| Require static-definition equality at persistent creation and exact module and revision checks at restore. | `Defer` to seams 01 and 07. | This seam preserves revision through authoring but does not define checkpoint or persistence policy. |
| Make `__agent_config__/0` the normalized public authority. | `Remove`. | `agent/0` performs canonical construction. The double-underscore functions remain private compiler metadata. |
| Treat generated interfaces as parity across all forms. | `Remove`. | Interface functions are module API. Definition parity is the common boundary. |
| Add extension declarations to Builder and Codec. | `Remove`. | A public pure lowerer gives data users access without storing Spark entities. |
| Reject all local route closures in common Agent validation. | `Remove`. | Direct custom routing remains supported. Codec reports that an unregistered value is not encodable. |
| Remove the legacy route-default struct exception immediately. | `Remove`. | Tests preserve it. Any removal needs a separate deprecation and replacement proof. |
| Encode only neutral definitions and reject instances. | `Remove`. | Current public examples and tests encode instances. Definition-first encoding keeps that input compatible. |
| Generate startup functions on every Agent module. | `Defer` to seam 09 and retain no new target here. | Jido instance and Agent Server seams own startup. |
| Remove explicit domain helpers. | `Remove`. | Applications can keep ordinary Elixir helpers. Generated helpers exist only when `define` is present. |
| Add portable named-function executable targets in this seam. | `Defer` to `jido_action`. | Executable resolution, validation, results, and telemetry need one lower-layer owner. |
| Claim that a definition revision pins loaded Action or Flow code. | `Remove`. | The pending Overview records executable code revision as a separate Turn and `jido_action` blocker. |
| Use `Jido.Agent` as the name of both core Agent and a downstream package abstraction. | `Remove`. | `Jido.Agent` is the current core value and macro. Downstream wrappers must use an unambiguous application module name. |
| State that five Basic fixtures have 15 tests and five parity tests. | `Correct`. | The Basic index has 16 runtime tests. Cross-form parity is one focused authoring test. |
| Link to the deleted Agent DSL migration report. | `Remove`. | Current code and tests are the canonical evidence. |
| Attribute interface inspiration to Ash code interfaces. | `Retain as rationale only`. | Explicit names and input mapping informed the design. Jido uses Spark directly and has no Ash dependency. |

## High-level work sequence

This sequence defines outcomes and gates. It is not an implementation plan.
Create the implementation plan after approval.

### Phase 0 — Resolve prerequisites and authoring decisions

- Requirements: all `AUTH-REQ` identifiers.
- Required outcome: approved form retention, parity boundary, module authority,
  Codec input rule, portable subset, extension rule, and revision dependency.
- Constraints: do not decide Agent fields, route selection, checkpoint restore,
  Plugin runtime, or Agent Server behavior.
- Compatibility: no runtime change.
- Verification: review all `AUTH-DEC` items and prerequisite blockers.
- Exit criteria: the user approves or changes each decision, and prerequisite
  drafts are approved or replaced by explicit assumptions.

### Phase 1 — Lock the retained authoring contract

- Requirements: `AUTH-REQ-001` to `AUTH-REQ-040`, `AUTH-REQ-049` to
  `AUTH-REQ-052`, `AUTH-REQ-055`, and `AUTH-REQ-057` to `AUTH-REQ-061`.
- Required outcome: public docs and tests state all supported forms, canonical
  parity, Spark and inline contracts, generated interfaces, Builder behavior,
  Codec separation, and extension validation.
- Constraints: preserve route and Plugin order and do not execute runtime work
  during authoring.
- Compatibility: no removal or deprecation.
- Verification: compile diagnostics, function docs and types, Builder, Codec,
  Registry, extension, Action, Flow, direct/live, and example tests.
- Exit criteria: every retained requirement has current or newly added passing
  evidence.

### Phase 2 — Align definition revision

- Requirements: `AUTH-REQ-014`, `AUTH-REQ-015`, `AUTH-REQ-039`, and
  `AUTH-REQ-048`.
- Required outcome: each applicable module, direct value, Builder, map, and
  Codec path preserves the approved Agent-seam revision.
- Constraints: revision does not define checkpoint, restore, state-version, or
  executable-code policy.
- Compatibility: existing module source and version-1 Codec documents follow
  the approved seam-01 migration rule.
- Verification: default, explicit, invalid, Builder, map, Codec version, and
  round-trip tests.
- Exit criteria: all applicable canonical definitions have the expected
  revision and old input behaves as approved.

### Phase 3 — Make Codec input and portability explicit

- Requirements: `AUTH-REQ-041` to `AUTH-REQ-047`.
- Required outcome: definition-first instance encoding and a tested
  Registry-resolvable static subset.
- Constraints: preserve instance calls, direct runtime predicates, closed
  tagged data, document limits, and trusted resolution.
- Compatibility: an instance continues to encode the same static document.
  A local closure remains valid outside Codec.
- Verification: non-idempotent state schema, definition equality, local and
  external predicates, missing identifiers, aliases, duplicate keys, hostile
  documents, and limits.
- Exit criteria: instance state cannot change static encoding, and every
  non-encodable valid definition gets the approved authoring error.

### Phase 4 — Publish the data extension boundary and complete types

- Requirements: `AUTH-REQ-033`, `AUTH-REQ-034`, `AUTH-REQ-039`,
  `AUTH-REQ-053`, `AUTH-REQ-054`, and `AUTH-REQ-056`.
- Required outcome: one documented pure lowerer and complete public types for
  Builder, Codec, Registry, and extension entries.
- Constraints: no runtime work, no stored Spark entities, and no interim error
  model outside seam 12.
- Compatibility: current Spark extension modules and lowered output remain
  valid.
- Verification: public docs and type checks, data-lowering parity, order,
  target claims, invalid results, and canonical validation tests.
- Exit criteria: a data author can lower extension input and then use direct,
  Builder, or Codec authoring without private functions.

### Phase 5 — Close downstream and release evidence

- Requirements: all approved `AUTH-REQ` identifiers.
- Required outcome: examples and dependent seams use the approved parity,
  revision, and extension contracts.
- Compatibility: no supported authoring API is removed without a separate
  approved staged migration.
- Verification: format, compile, focused tests, full package tests, Basic
  examples, public-only extension fixture, and compatible V3 package matrix.
- Exit criteria: the acceptance matrix has no `Missing` or `Conflict` state for
  an approved requirement.

## Acceptance matrix

| Requirement | Evidence now | Required evidence | Evidence state |
| --- | --- | --- | --- |
| `AUTH-REQ-001` to `AUTH-REQ-008` | Agent validation; authoring contract tests; parity test | Representative parity matrix and public contract inventory | `Proven` for current covered behavior |
| `AUTH-REQ-009` to `AUTH-REQ-013` | Agent macro and DSL compiler; mixed-field diagnostics | Explicit private-metadata and canonical-`agent/0` contract tests | `Partial` |
| `AUTH-REQ-014` and `AUTH-REQ-015` | No revision field exists | Module default, explicit, invalid, direct, and behavior-only revision cases | `Missing` |
| `AUTH-REQ-016` to `AUTH-REQ-020` | Inline macro and reuse tests | Cross-package inline Action compatibility against release `jido_action` | `Proven` in current workspace |
| `AUTH-REQ-021` to `AUTH-REQ-034` | Compiler, generator, interface, docs, types, packaging, and diagnostic tests | Public API inventory and approved seam-12 error cases | `Proven` for current interface behavior |
| `AUTH-REQ-035` to `AUTH-REQ-038` | Builder code and focused tests | Complete public types and no-execution case in public-only fixture | `Proven` for behavior; types are partial |
| `AUTH-REQ-039` | Builder has no revision field | Builder revision preservation and old-input cases | `Missing` |
| `AUTH-REQ-040` | Serialization contract test | Keep authoring, checkpoint, and persistence format separation after revision work | `Proven` |
| `AUTH-REQ-041` and `AUTH-REQ-042` | Static document exclusion works; instance input parses state again | Definition-first instance tests with a non-idempotent state transform | `Conflict` |
| `AUTH-REQ-043` to `AUTH-REQ-047` | Codec, Data, Registry, alias, hostile-input, and limit tests | Focused valid-local-closure versus non-encodable-Codec test and approved error | `Partial` |
| `AUTH-REQ-048` | Codec version 1 has no revision | Versioned revision round trip plus existing-document compatibility fixtures | `Missing` |
| `AUTH-REQ-049` | Plugin Codec tests | Preserve through Agent Codec version change | `Proven` |
| `AUTH-REQ-050` to `AUTH-REQ-052` | Extension host and extension tests | Public-only extension fixture | `Proven` in current Spark host |
| `AUTH-REQ-053` and `AUTH-REQ-054` | Pure `lower/3` exists with `@doc false`; Builder and Codec accept lowered core data | Public data-lowering docs, types, and direct/Builder/Codec parity test | `Partial` |
| `AUTH-REQ-055` | After-verify compiler path and later-module test | Preserve in compatible package set | `Proven` |
| `AUTH-REQ-056` | Current authoring errors are structured but not final | Seam-12 normalization and bang parity across every public entry | `Partial` |
| `AUTH-REQ-057` to `AUTH-REQ-060` | Generated constructor, packaging, docs, and direct/live tests | Preserve in the public interface acceptance set | `Proven` |
| `AUTH-REQ-061` | Builder module-input parity test | Preserve through revision and module-authority changes | `Proven` for current definition result |

## Migration and compatibility

No removal or deprecation is approved in this seam.

| Area | Compatibility rule and gate |
| --- | --- |
| Forms | Keep module, Spark, direct map and keyword, Builder, Codec, and neutral definitions. |
| Module metadata | Keep double-underscore compiler functions private. Use `agent/0` for canonical data. |
| Revision | Add the seam-01 revision without removing an old input. Keep the approved version-1 Codec read rule. |
| Inline Actions | Keep current syntax and `route_action/1`. Test against the intended `jido_action` release source. |
| Interfaces | Keep generated names, arities, docs, types, packaging, and live delegation. Interface functions remain module-only. |
| Builder | Keep the first-error and order rules. Add fields and types without changing the staged workflow. |
| Codec instances | Keep instance input. Change internal handling to static definition-first encoding and preserve the produced document. |
| Route predicates | Keep valid direct predicates. Codec requires trusted Registry identifiers and external unary captures. |
| Route defaults | Keep explicit plain maps and the legacy tuple map-struct exception. Any unification needs separate deprecation. |
| Extensions | Keep Spark host behavior. Add a public pure lowerer. Do not store extension entities in Codec data. |
| Errors | Adopt approved seam-12 codes by boundary. Do not expose private compiler or Registry data in error output. |
| Cross-package versions | Do not name a stale `jido_action` version. Test the declared release-compatible package set. |

## Assumptions and blockers

| ID | Type | Owner | Statement | Resolution needed |
| --- | --- | --- | --- | --- |
| `AUTH-BLK-001` | `Blocker` | 00 Overview | Shared form retention, revision, and compatibility requirements are pending approval. | Approve them or replace them with explicit seam-02 assumptions. |
| `AUTH-BLK-002` | `Blocker` | 90 Package boundaries | Extension categories and cross-package release gates are pending approval. | Approve or change the package boundary. |
| `AUTH-BLK-003` | `Blocker` | 12 Errors and contracts | Stable authoring errors, codes, and bang rules are pending approval. | Approve them before final error alignment. |
| `AUTH-BLK-004` | `Blocker` | 01 Agent | The definition-revision field, default, and old-document rule are pending approval. | Approve or change the Agent revision contract. |
| `AUTH-BLK-005` | `Assumption` | 02 Agent authoring | Parity applies to canonical definitions, not module functions or source syntax. | Approve or change `AUTH-DEC-002`. |
| `AUTH-BLK-006` | `Assumption` | 02 Agent authoring | Codec keeps instance input and changes to definition-first static encoding. | Approve or change `AUTH-DEC-004`. |
| `AUTH-BLK-007` | `Assumption` | 02 Agent authoring and `jido_signal` | Direct Router predicates can exceed the Codec portable subset. | Approve or require one stricter common predicate rule. |
| `AUTH-BLK-008` | `Assumption` | 02 Agent authoring | Data extensions lower before Builder or Codec and do not enter documents. | Approve or change `AUTH-DEC-006`. |
| `AUTH-BLK-009` | `Blocker` | 04 Turn evaluation and `jido_action` | Definition revision does not pin loaded Action or Flow code. | Define executable code-revision scope at the execution boundary. |

## Completion criteria

- [ ] The user has approved or changed each `AUTH-DEC` item.
- [ ] Prerequisite drafts are approved or replaced by explicit assumptions.
- [ ] Every approved `AUTH-REQ` item has `Proven` evidence.
- [ ] No unresolved `Conflict` remains in the acceptance matrix.
- [ ] All supported forms produce equal canonical definitions for equivalent
      source data.
- [ ] Module-only interfaces and source-only extension syntax are not described
      as canonical Agent data.
- [ ] Definition revision passes module, direct, Builder, map, and Codec cases
      required by seam 01.
- [ ] Codec instance input, portable subset, Registry safety, and document
      limits have passing evidence.
- [ ] Public Builder, Codec, Registry, generated-interface, and extension docs
      and types match the approved contract.
- [ ] No checkpoint, restore, route-selection, Plugin-runtime, commit, Agent
      Server, or identity contract is decided in this seam.
- [ ] Dependent seams use the approved definition and parity contract.
- [ ] After approval, a separate formal implementation plan defines tasks.
